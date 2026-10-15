"""Rule-violation tests for the shared framework and master data.

Each test tries to break one rule from Section 5 and checks that the
database itself refuses. Test names say which rule they prove.
Module owners copy this pattern for their own tables (min. 5 tests per module).
"""
import psycopg
import pytest

from conftest import (
    CHECK_VIOLATION,
    FOREIGN_KEY_VIOLATION,
    INSUFFICIENT_PRIVILEGE,
    UNIQUE_VIOLATION,
    DSN,
    make_user,
    ref_code_id,
    violates,
)


def india_id(db):
    return db.execute("SELECT id FROM mst.country WHERE iso2_code = 'IN'").fetchone()[0]


def karnataka_id(db):
    return db.execute("SELECT id FROM mst.state WHERE iso_code = 'IN-KA'").fetchone()[0]


# ---------------------------------------------------------------------------
# Rule 3: standard domains
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("value", ["josé@Example.com", "no-at-sign", "a@b"])
def test_rule3_email_must_be_lowercase_and_well_formed(db, value):
    with violates(db, CHECK_VIOLATION):
        db.execute("SELECT %s::core.email_address", (value,))


def test_rule3_email_accepts_valid_lowercase(db):
    assert db.execute("SELECT 'priya.r@example.in'::core.email_address").fetchone()[0]


@pytest.mark.parametrize("value", ["9876543210", "+0919876543", "+91 98765 43210"])
def test_rule3_phone_must_be_e164(db, value):
    with violates(db, CHECK_VIOLATION):
        db.execute("SELECT %s::core.phone_e164", (value,))


def test_rule3_person_name_accepts_any_script(db):
    for name in ["ರಂಗನಾಥ್", "भार्गव", "Dhanush C N", "O'Brien-Nakamura"]:
        assert db.execute("SELECT %s::core.person_name", (name,)).fetchone()[0] == name


def test_rule3_person_name_max_150_characters(db):
    with violates(db, "22001"):  # string_data_right_truncation
        db.execute("SELECT %s::core.person_name", ("x" * 151,))


@pytest.mark.parametrize("value", [101, -1])
def test_rule3_percentage_range_0_to_100(db, value):
    with violates(db, CHECK_VIOLATION):
        db.execute("SELECT %s::core.percentage", (value,))


def test_rule3_latitude_range(db):
    with violates(db, CHECK_VIOLATION):
        db.execute("SELECT 91::core.latitude")


def test_rule3_enumeration_value_must_belong_to_its_own_type(db):
    """A city's coordinate_source cannot hold an APPLICATION_STATUS value (composite FK)."""
    wrong_type_value = ref_code_id(db, "APPLICATION_STATUS", "APPLIED")
    with violates(db, FOREIGN_KEY_VIOLATION):
        db.execute(
            """INSERT INTO mst.city (state_id, english_name, latitude, longitude, coordinate_source_ref_code_id)
               VALUES (%s, 'Testpur', 12.9, 77.6, %s)""",
            (karnataka_id(db), wrong_type_value),
        )


def test_rule3_enumeration_type_column_cannot_be_changed(db):
    with violates(db, CHECK_VIOLATION):
        db.execute("UPDATE mst.skill SET skill_category_code_type_id = skill_category_code_type_id + 1")


def test_rule3_coordinates_come_in_pairs_with_a_source(db):
    with violates(db, CHECK_VIOLATION):
        db.execute(
            "INSERT INTO mst.city (state_id, english_name, latitude) VALUES (%s, 'Halfpur', 12.9)",
            (karnataka_id(db),),
        )


# ---------------------------------------------------------------------------
# Rule 5: no sentinel values for "missing"
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("sentinel", ["", "  ", "NA", "n/a", "NULL", "None", "-"])
def test_rule5_sentinels_rejected_in_names(db, sentinel):
    with violates(db, CHECK_VIOLATION):
        db.execute("SELECT %s::core.person_name", (sentinel,))


def test_rule5_sentinels_rejected_in_free_text(db):
    with violates(db, CHECK_VIOLATION):
        db.execute(
            "INSERT INTO mst.industry (english_name) VALUES ('N/A')"
        )


# ---------------------------------------------------------------------------
# Rule 4: audit columns
# ---------------------------------------------------------------------------

def test_rule4_writes_without_an_actor_are_refused():
    """No app.user_id = no write. This is what makes created_by trustworthy."""
    with psycopg.connect(DSN) as conn:
        with violates(conn, INSUFFICIENT_PRIVILEGE):
            conn.execute("INSERT INTO mst.industry (english_name) VALUES ('Anonymous Industry')")
        conn.rollback()


def test_rule4_audit_columns_filled_and_creation_is_immutable(db):
    row_id = db.execute(
        "INSERT INTO mst.industry (english_name) VALUES ('Audit Test Industry') RETURNING id"
    ).fetchone()[0]

    editor = make_user(db, "ADMIN")
    db.execute("SELECT set_config('app.user_id', %s, true)", (str(editor),))
    db.execute(
        "UPDATE mst.industry SET english_name = 'Audit Test Renamed', created_by = 999 WHERE id = %s",
        (row_id,),
    )
    created_by, updated_by = db.execute(
        "SELECT created_by, updated_by FROM mst.industry WHERE id = %s", (row_id,)
    ).fetchone()
    assert created_by == 1, "created_by must not change after insert"
    assert updated_by == editor, "updated_by must be the acting user"


def test_rule2_audit_actor_must_be_a_real_account(db):
    db.execute("SELECT set_config('app.user_id', '987654321', true)")
    with violates(db, FOREIGN_KEY_VIOLATION):
        db.execute("INSERT INTO mst.industry (english_name) VALUES ('Ghost Industry')")


# ---------------------------------------------------------------------------
# Rule 4 / Rule 10: append-only and soft delete helpers
# ---------------------------------------------------------------------------

def test_rule10_append_only_rejects_update_delete_and_truncate(db):
    db.execute(
        "CREATE TABLE mst.scratch_ledger_entry (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, note core.text_100 NOT NULL)"
    )
    db.execute("SELECT core.add_creation_columns('mst.scratch_ledger_entry')")
    db.execute("SELECT core.make_append_only('mst.scratch_ledger_entry')")
    db.execute("INSERT INTO mst.scratch_ledger_entry (note) VALUES ('credit 100')")

    for statement in [
        "UPDATE mst.scratch_ledger_entry SET note = 'credit 1000'",
        "DELETE FROM mst.scratch_ledger_entry",
        "TRUNCATE mst.scratch_ledger_entry",
    ]:
        with violates(db, INSUFFICIENT_PRIVILEGE):
            db.execute(statement)


def test_rule4_soft_deleted_rows_hidden_from_application_role(db):
    db.execute(
        "CREATE TABLE mst.scratch_post (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, title core.text_100 NOT NULL)"
    )
    db.execute("SELECT core.enable_soft_delete('mst.scratch_post')")
    db.execute("GRANT SELECT ON mst.scratch_post TO talentra_app")
    db.execute("INSERT INTO mst.scratch_post (title) VALUES ('live'), ('removed')")
    db.execute("UPDATE mst.scratch_post SET deleted_at = now(), deleted_by = 1 WHERE title = 'removed'")

    db.execute("SET LOCAL ROLE talentra_app")
    visible = [r[0] for r in db.execute("SELECT title FROM mst.scratch_post")]
    assert visible == ["live"]


def test_rule4_application_soft_deletes_but_never_hard_deletes(db):
    db.execute(
        "CREATE TABLE mst.scratch_ticket (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, subject core.text_100 NOT NULL)"
    )
    db.execute("SELECT core.add_audit_columns('mst.scratch_ticket')")
    db.execute("SELECT core.enable_soft_delete('mst.scratch_ticket')")
    db.execute("GRANT SELECT, INSERT, UPDATE ON mst.scratch_ticket TO talentra_app")
    db.execute("INSERT INTO mst.scratch_ticket (subject) VALUES ('login issue')")

    db.execute("SET LOCAL ROLE talentra_app")
    db.execute("UPDATE mst.scratch_ticket SET deleted_at = now(), deleted_by = 1")
    assert db.execute("SELECT count(*) FROM mst.scratch_ticket").fetchone()[0] == 0
    with violates(db, INSUFFICIENT_PRIVILEGE):
        db.execute("DELETE FROM mst.scratch_ticket")


def test_rule4_soft_delete_needs_both_timestamp_and_actor(db):
    db.execute(
        "CREATE TABLE mst.scratch_note (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, body core.text_100 NOT NULL)"
    )
    db.execute("SELECT core.enable_soft_delete('mst.scratch_note')")
    db.execute("INSERT INTO mst.scratch_note (body) VALUES ('x')")
    with violates(db, CHECK_VIOLATION):
        db.execute("UPDATE mst.scratch_note SET deleted_at = now()")


# ---------------------------------------------------------------------------
# Rule 7: multilingual
# ---------------------------------------------------------------------------

def test_rule7_display_name_in_requested_language(db):
    applied = ref_code_id(db, "APPLICATION_STATUS", "APPLIED")
    assert db.execute("SELECT mst.ref_code_display_name(%s, 'kn')", (applied,)).fetchone()[0] == "ಅರ್ಜಿ ಸಲ್ಲಿಸಲಾಗಿದೆ"


def test_rule7_missing_translation_falls_back_to_default_language(db):
    applied = ref_code_id(db, "APPLICATION_STATUS", "APPLIED")
    assert db.execute("SELECT mst.ref_code_display_name(%s, 'ta')", (applied,)).fetchone()[0] == "Applied"
    assert db.execute("SELECT mst.ui_label_text('profile.save.button', 'kn')").fetchone()[0] == "Save profile"


def test_rule7_only_one_default_language(db):
    with violates(db, UNIQUE_VIOLATION):
        db.execute("UPDATE mst.language SET is_default = true WHERE iso_code = 'hi'")


def test_rule7_utf8_end_to_end(db):
    assert db.execute("SELECT pg_encoding_to_char(encoding) FROM pg_database WHERE datname = current_database()").fetchone()[0] == "UTF8"


# ---------------------------------------------------------------------------
# Rule 2: master data cannot be deleted while referenced
# ---------------------------------------------------------------------------

def test_rule2_referenced_master_rows_cannot_be_deleted(db):
    with violates(db, FOREIGN_KEY_VIOLATION):
        db.execute("DELETE FROM mst.country WHERE iso2_code = 'IN'")


def test_rule2_duplicate_skill_names_rejected_case_insensitively(db):
    other = ref_code_id(db, "SKILL_CATEGORY", "TECHNICAL")
    with violates(db, UNIQUE_VIOLATION):
        db.execute(
            "INSERT INTO mst.skill (english_name, skill_category_ref_code_id) VALUES (' java', %s)", (other,)
        )
