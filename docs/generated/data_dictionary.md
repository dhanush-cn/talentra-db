# Talentra data dictionary

Generated from the live schema on 2026-10-15 08:58 UTC. Do not edit by hand: change the column comments and regenerate.

55 tables.

## Master data (`mst`)

### `mst.city`

Cities and towns.

_lifecycle: deactivate_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | public | Surrogate key. |
| `state_id` | `bigint` | no | public | State the city is in. Covered by uq_city_state_id_english_name. |
| `english_name` | `core.text_100` | no | public | Name in English. |
| `latitude` | `core.latitude` | yes: city not geocoded yet | public | WGS84 latitude, 6 decimals. |
| `longitude` | `core.longitude` | yes: city not geocoded yet | public | WGS84 longitude, 6 decimals. |
| `is_active` | `boolean` | no | public | Selectable. Default true. |
| `coordinate_source_code_type_id` | `bigint` | no | internal | Fixed to code_type COORDINATE_SOURCE; makes the composite FK type-safe. |
| `coordinate_source_ref_code_id` | `bigint` | yes: city not geocoded yet | internal | Value from mst.ref_code. Enumeration `COORDINATE_SOURCE`. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

### `mst.code_type`

Catalogue of enumerations. Each fixed value list in any module is one row here.

_lifecycle: deactivate_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | public | Surrogate key. |
| `code` | `core.code` | no | public | Stable machine name, e.g. APPLICATION_STATUS. |
| `english_name` | `core.text_100` | no | public | Name for administrators. |
| `description` | `core.text_1000` | yes: optional explanation for administrators | public | What the list is used for. |
| `owning_module` | `core.code` | no | internal | Module responsible for the list, e.g. JOB, GIG. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

### `mst.country`

ISO 3166-1 countries.

_lifecycle: deactivate_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | public | Surrogate key. |
| `iso2_code` | `character varying(2)` | no | public | ISO 3166-1 alpha-2, e.g. IN. |
| `iso3_code` | `character varying(3)` | no | public | ISO 3166-1 alpha-3, e.g. IND. |
| `english_name` | `core.text_100` | no | public | Name in English. |
| `phone_calling_code` | `character varying(4)` | no | public | E.164 country calling code without +, e.g. 91. |
| `currency_id` | `bigint` | no | public | Default currency. |
| `is_active` | `boolean` | no | public | Selectable. Default true. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

### `mst.currency`

ISO 4217 currencies. Every money column pairs with a currency_id.

_lifecycle: deactivate_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | public | Surrogate key. |
| `iso_code` | `character varying(3)` | no | public | ISO 4217 code, e.g. INR. |
| `english_name` | `core.text_100` | no | public | Name in English. |
| `minor_unit` | `smallint` | no | public | Decimal places used by the currency (0–4). |
| `is_active` | `boolean` | no | public | Accepted for new transactions. Default true. |
| `sort_order` | `core.sort_order` | no | public | Display order. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

### `mst.industry`

Industry classification with optional parent.

_lifecycle: deactivate_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | public | Surrogate key. |
| `parent_industry_id` | `bigint` | yes: top-level industry | public | Parent industry. |
| `english_name` | `core.text_255` | no | public | Name in English. |
| `is_active` | `boolean` | no | public | Selectable. Default true. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

### `mst.institution`

Education providers; used by candidate education and campus hiring.

_lifecycle: deactivate_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | public | Surrogate key. |
| `english_name` | `core.text_255` | no | public | Official name. |
| `city_id` | `bigint` | yes: online or multi-campus provider | public | City of the main campus. |
| `is_active` | `boolean` | no | public | Selectable. Default true. |
| `institution_type_code_type_id` | `bigint` | no | internal | Fixed to code_type INSTITUTION_TYPE; makes the composite FK type-safe. |
| `institution_type_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `INSTITUTION_TYPE`. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

### `mst.job_role`

Standard job roles used to classify jobs and candidate experience.

_lifecycle: deactivate_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | public | Surrogate key. |
| `industry_id` | `bigint` | no | public | Industry the role belongs to. Covered by uq_job_role_industry_id_english_name. |
| `english_name` | `core.text_255` | no | public | Name in English, e.g. Backend Engineer. |
| `is_active` | `boolean` | no | public | Selectable. Default true. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

### `mst.language`

Languages for UI and user content.

_lifecycle: deactivate_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | public | Surrogate key. |
| `iso_code` | `character varying(10)` | no | public | ISO 639-1/639-3 code with optional region, e.g. en, kn, en-IN. |
| `english_name` | `core.text_100` | no | public | Name in English. |
| `native_name` | `core.text_100` | no | public | Name in its own script, e.g. ಕನ್ನಡ. |
| `is_default` | `boolean` | no | public | Fallback language for missing translations. Exactly one row is true. Default false. |
| `is_ui_supported` | `boolean` | no | public | UI strings are maintained in this language. Default false. |
| `is_active` | `boolean` | no | public | Available for selection. Default true. |
| `sort_order` | `core.sort_order` | no | public | Display order in pickers. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

### `mst.qualification`

Degrees, diplomas and certificates.

_lifecycle: deactivate_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | public | Surrogate key. |
| `english_name` | `core.text_255` | no | public | Full name, e.g. Bachelor of Engineering. |
| `short_name` | `core.text_100` | no | public | Abbreviation shown in lists, e.g. B.E. |
| `is_active` | `boolean` | no | public | Selectable. Default true. |
| `qualification_level_code_type_id` | `bigint` | no | internal | Fixed to code_type QUALIFICATION_LEVEL; makes the composite FK type-safe. |
| `qualification_level_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `QUALIFICATION_LEVEL`. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

### `mst.ref_code`

Values of every enumeration. Never deleted; retired values set is_active = false.

_lifecycle: deactivate_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | public | Surrogate key. |
| `code_type_id` | `bigint` | no | public | Enumeration this value belongs to. |
| `code` | `core.code` | no | public | Stable machine value, e.g. SHORTLISTED. Never shown to users. |
| `sort_order` | `core.sort_order` | no | public | Display and pipeline order. |
| `is_active` | `boolean` | no | public | Selectable for new rows. Default true. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

### `mst.ref_code_translation`

Display name of each enumeration value per language.

_lifecycle: hard_delete_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | public | Surrogate key. |
| `ref_code_id` | `bigint` | no | public | Value being translated. |
| `language_id` | `bigint` | no | public | Language of display_name. |
| `display_name` | `core.text_255` | no | public | Text shown to users. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

### `mst.skill`

Skill catalogue shared by candidates, jobs and gigs.

_lifecycle: deactivate_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | public | Surrogate key. |
| `english_name` | `core.text_100` | no | public | Canonical name, e.g. PostgreSQL. |
| `normalized_name` | `character varying(100)` | no | public | Lowercased, trimmed name; prevents duplicates such as "Java" and "java ". |
| `is_active` | `boolean` | no | public | Selectable. Default true. |
| `skill_category_code_type_id` | `bigint` | no | internal | Fixed to code_type SKILL_CATEGORY; makes the composite FK type-safe. |
| `skill_category_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `SKILL_CATEGORY`. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

### `mst.state`

First-level subdivisions (ISO 3166-2).

_lifecycle: deactivate_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | public | Surrogate key. |
| `country_id` | `bigint` | no | public | Country the subdivision belongs to. |
| `iso_code` | `character varying(10)` | no | public | ISO 3166-2 code, e.g. IN-KA. |
| `english_name` | `core.text_100` | no | public | Name in English. |
| `is_union_territory` | `boolean` | no | public | Union territory rather than state. Default false. |
| `is_active` | `boolean` | no | public | Selectable. Default true. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

### `mst.ui_label`

UI string keys. Keys are never displayed to users.

_lifecycle: hard_delete_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | public | Surrogate key. |
| `label_key` | `core.label_key` | no | public | Dotted key, e.g. job.apply.button. |
| `description` | `core.text_1000` | yes: optional context for translators | public | Where and how the string appears. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

### `mst.ui_label_translation`

One row per UI key and language.

_lifecycle: hard_delete_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | public | Surrogate key. |
| `ui_label_id` | `bigint` | no | public | Key being translated. |
| `language_id` | `bigint` | no | public | Language of label_text. |
| `label_text` | `core.text_1000` | no | public | Text shown to users. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

## Profile (`prf`)

### `prf.assessment`

Self-assessments, platform tests and employer tests.

_lifecycle: deactivate_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | public | Surrogate key. |
| `title` | `core.text_255` | no | public | Assessment name. |
| `description` | `core.text_1000` | yes: no description written | public | What it measures. |
| `skill_id` | `bigint` | yes: general aptitude, not tied to one skill | public | Skill assessed. |
| `organisation_id` | `bigint` | yes: not an employer test | internal | Employer that owns the test. |
| `max_score` | `numeric(7,2)` | no | public | Highest possible score (> 0). |
| `pass_score` | `numeric(7,2)` | yes: no pass mark, e.g. self-assessment | public | Minimum passing score. |
| `is_active` | `boolean` | no | public | Available to take. Default true. |
| `assessment_type_code_type_id` | `bigint` | no | internal | Fixed to code_type ASSESSMENT_TYPE; makes the composite FK type-safe. |
| `assessment_type_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `ASSESSMENT_TYPE`. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

### `prf.candidate_activity_event`

Candidate activity log: sign-ins, profile updates, resume uploads and downloads.

_lifecycle: append_only · partitioned_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key (unique with occurred_at). |
| `user_account_id` | `bigint` | no | internal | Account that acted. |
| `candidate_profile_id` | `bigint` | yes: account had no candidate profile yet, e.g. first sign-in | internal | Profile affected. |
| `occurred_at` | `timestamp with time zone` | no | internal | When it happened (UTC); partition key. |
| `detail` | `core.text_255` | yes: event type says everything | internal | Short machine-readable detail, never personal data. |
| `activity_type_code_type_id` | `bigint` | no | internal | Fixed to code_type ACTIVITY_TYPE; makes the composite FK type-safe. |
| `activity_type_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `ACTIVITY_TYPE`. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was recorded (UTC). |
| `created_by` | `bigint` | no | internal | user_account that recorded the row. |

### `prf.candidate_assessment_result`

Every assessment attempt and its score. Retakes are new rows.

_lifecycle: append_only_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key. |
| `candidate_profile_id` | `bigint` | no | internal | Candidate. |
| `assessment_id` | `bigint` | no | internal | Assessment taken. |
| `score_value` | `numeric(7,2)` | no | personal | Raw score. |
| `score_percent` | `core.percentage` | no | personal | Score as a percentage of max_score. |
| `attempted_at` | `timestamp with time zone` | no | internal | When the attempt was made (UTC). |
| `duration_seconds` | `core.positive_int` | yes: not timed, e.g. self-assessment | internal | Time taken. |
| `assessment_result_code_type_id` | `bigint` | no | internal | Fixed to code_type ASSESSMENT_RESULT; makes the composite FK type-safe. |
| `assessment_result_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `ASSESSMENT_RESULT`. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was recorded (UTC). |
| `created_by` | `bigint` | no | internal | user_account that recorded the row. |

### `prf.candidate_bookmark`

Candidates saved by an employer, recruiter or consultant (current state). History is in candidate_bookmark_event.

_lifecycle: soft_delete · row-level security_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key. |
| `owner_user_account_id` | `bigint` | no | internal | Who saved the candidate. |
| `organisation_id` | `bigint` | yes: saved by an independent consultant | internal | Organisation the owner acted for. |
| `candidate_profile_id` | `bigint` | no | internal | Candidate saved. |
| `note` | `core.text_1000` | yes: no note | internal | Private note by the owner. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |
| `deleted_at` | `timestamp with time zone` | yes: row is live | internal | When the row was soft-deleted (UTC). |
| `deleted_by` | `bigint` | yes: row is live | internal | user_account that soft-deleted the row. |

### `prf.candidate_bookmark_event`

Bookmark and shortlist history for employers and recruiters, written by trigger.

_lifecycle: append_only_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key. |
| `candidate_bookmark_id` | `bigint` | no | internal | Bookmark that changed. |
| `bookmark_action_code_type_id` | `bigint` | no | internal | Fixed to code_type BOOKMARK_ACTION; makes the composite FK type-safe. |
| `bookmark_action_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `BOOKMARK_ACTION`. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was recorded (UTC). |
| `created_by` | `bigint` | no | internal | user_account that recorded the row. |

### `prf.candidate_contact`

Candidate email and phone numbers, encrypted at rest.

_lifecycle: hard_delete_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key. |
| `candidate_profile_id` | `bigint` | no | internal | Profile the contact belongs to. |
| `value_encrypted` | `bytea` | no | personal | Email (lowercase) or E.164 phone, encrypted with core.pii_encrypt. |
| `value_hmac` | `bytea` | no | personal | HMAC-SHA256 blind index of the normalised value; exact-match lookup and duplicate detection without decrypting. |
| `value_masked` | `core.text_100` | no | personal | Masked value shown before a profile download, e.g. pr***@gmail.com. |
| `phone_country_id` | `bigint` | yes: contact is an email | personal | Country of the phone number. |
| `is_primary` | `boolean` | no | internal | Primary contact of its type; at most one per type. Default false. |
| `is_verified` | `boolean` | no | internal | Ownership confirmed by OTP or link. Default false. |
| `verified_at` | `timestamp with time zone` | yes: not verified | internal | When ownership was confirmed (UTC). |
| `contact_type_code_type_id` | `bigint` | no | internal | Fixed to code_type CONTACT_TYPE; makes the composite FK type-safe. |
| `contact_type_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `CONTACT_TYPE`. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

### `prf.candidate_course_enrolment`

Courses a candidate has enrolled in.

_lifecycle: hard_delete_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key. |
| `candidate_profile_id` | `bigint` | no | internal | Candidate. |
| `course_id` | `bigint` | no | public | Course. |
| `enrolled_at` | `timestamp with time zone` | no | internal | Enrolment time (UTC). |
| `completed_at` | `timestamp with time zone` | yes: not completed | public | Completion time (UTC). |
| `certificate_url` | `core.text_1000` | yes: no certificate issued | public | Certificate link. |
| `enrolment_status_code_type_id` | `bigint` | no | internal | Fixed to code_type ENROLMENT_STATUS; makes the composite FK type-safe. |
| `enrolment_status_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `ENROLMENT_STATUS`. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

### `prf.candidate_education`

Degrees, diplomas and certificates held or in progress.

_lifecycle: hard_delete_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key. |
| `candidate_profile_id` | `bigint` | no | internal | Candidate. |
| `qualification_id` | `bigint` | no | public | Qualification from the catalogue. |
| `institution_id` | `bigint` | yes: institution not in the catalogue; see institution_name | public | Institution. |
| `institution_name` | `core.text_255` | yes: institution chosen from the catalogue | public | Institution name as typed. |
| `specialisation` | `core.text_255` | yes: not applicable or not stated | public | Branch or major, e.g. Information Science. |
| `start_date` | `date` | yes: not stated | public | Start date. |
| `end_date` | `date` | yes: ongoing or not stated; see is_ongoing | public | Completion date. |
| `is_ongoing` | `boolean` | no | public | Still studying. Default false. |
| `score_value` | `numeric(6,2)` | yes: not disclosed | personal | Score on score_scale (percentage 0–100, CGPA 0–10 or GPA 0–4). |
| `score_scale_code_type_id` | `bigint` | no | internal | Fixed to code_type SCORE_SCALE; makes the composite FK type-safe. |
| `score_scale_ref_code_id` | `bigint` | yes: score not disclosed | internal | Value from mst.ref_code. Enumeration `SCORE_SCALE`. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

### `prf.candidate_language`

Languages a candidate knows.

_lifecycle: hard_delete_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key. |
| `candidate_profile_id` | `bigint` | no | internal | Candidate. |
| `language_id` | `bigint` | no | public | Language. |
| `can_read` | `boolean` | no | public | Can read. Default true. |
| `can_write` | `boolean` | no | public | Can write. Default true. |
| `can_speak` | `boolean` | no | public | Can speak. Default true. |
| `proficiency_code_type_id` | `bigint` | no | internal | Fixed to code_type PROFICIENCY_LEVEL; makes the composite FK type-safe. |
| `proficiency_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `PROFICIENCY_LEVEL`. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

### `prf.candidate_preferred_location`

Cities a candidate is willing to work in.

_lifecycle: hard_delete_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key. |
| `candidate_profile_id` | `bigint` | no | internal | Candidate. |
| `city_id` | `bigint` | no | public | Preferred city. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

### `prf.candidate_profile`

One profile per candidate.

_lifecycle: soft_delete · row-level security_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key. |
| `public_id` | `uuid` | no | internal | Identifier used in URLs and APIs. |
| `user_account_id` | `bigint` | no | internal | Account that owns the profile (1:1). |
| `full_name` | `core.person_name` | no | personal | Name as the candidate writes it; any script, no assumed word order. |
| `preferred_name` | `core.person_name` | yes: candidate uses full_name | personal | Name to address the candidate by. |
| `date_of_birth` | `date` | yes: not provided | personal | Date of birth. |
| `nationality_country_id` | `bigint` | yes: not provided | personal | Nationality. |
| `current_city_id` | `bigint` | yes: not provided | personal | City the candidate lives in. |
| `headline` | `core.text_255` | yes: not written yet | public | One-line summary shown in search results. |
| `summary` | `core.text_4000` | yes: not written yet | public | Profile summary, stored as entered. |
| `summary_language_id` | `bigint` | yes: language not detected or no summary | internal | Language of summary (Rule 7). |
| `is_fresher` | `boolean` | no | public | No prior work experience. Default false. |
| `total_experience_months` | `core.non_negative_int` | yes: not stated | public | Total experience as stated by the candidate. |
| `notice_period_days` | `core.non_negative_int` | yes: not stated | public | Notice period in days. |
| `is_open_to_work` | `boolean` | no | public | Actively looking. Default true. |
| `salary_currency_id` | `bigint` | yes: no salary disclosed | personal | Currency of both salary amounts. |
| `current_salary_amount` | `core.money_amount` | yes: not disclosed or not applicable; see current_salary_disclosure | personal | Current annual salary. |
| `expected_salary_amount` | `core.money_amount` | yes: not disclosed or not applicable; see expected_salary_disclosure | personal | Expected annual salary. |
| `completion_percent` | `core.percentage` | no | internal | Profile completion score 0–100, recomputed by prf.refresh_completion(). |
| `source_record_id` | `core.text_100` | yes: registered directly on the platform | internal | Record id in the source system; natural key with source_system. |
| `duplicate_of_candidate_profile_id` | `bigint` | yes: not identified as a duplicate | internal | Surviving profile when this one was merged as a duplicate. |
| `last_active_at` | `timestamp with time zone` | yes: never active since registration | internal | Last sign-in or profile activity (UTC); drives inactivity retention. |
| `gender_code_type_id` | `bigint` | no | internal | Fixed to code_type GENDER; makes the composite FK type-safe. |
| `gender_ref_code_id` | `bigint` | yes: candidate has not answered | internal | Value from mst.ref_code. Enumeration `GENDER`. |
| `profile_visibility_code_type_id` | `bigint` | no | internal | Fixed to code_type PROFILE_VISIBILITY; makes the composite FK type-safe. |
| `profile_visibility_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `PROFILE_VISIBILITY`. |
| `current_salary_disclosure_code_type_id` | `bigint` | no | internal | Fixed to code_type DISCLOSURE_STATUS; makes the composite FK type-safe. |
| `current_salary_disclosure_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `DISCLOSURE_STATUS`. |
| `expected_salary_disclosure_code_type_id` | `bigint` | no | internal | Fixed to code_type DISCLOSURE_STATUS; makes the composite FK type-safe. |
| `expected_salary_disclosure_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `DISCLOSURE_STATUS`. |
| `source_system_code_type_id` | `bigint` | no | internal | Fixed to code_type SOURCE_SYSTEM; makes the composite FK type-safe. |
| `source_system_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `SOURCE_SYSTEM`. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |
| `deleted_at` | `timestamp with time zone` | yes: row is live | internal | When the row was soft-deleted (UTC). |
| `deleted_by` | `bigint` | yes: row is live | internal | user_account that soft-deleted the row. |

### `prf.candidate_project`

Projects on a profile, including gig projects (the Gig module links completed assignments here).

_lifecycle: hard_delete_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key. |
| `candidate_profile_id` | `bigint` | no | internal | Candidate. |
| `title` | `core.text_255` | no | public | Project name. |
| `role_description` | `core.text_255` | no | public | Candidate's role on the project. |
| `start_date` | `date` | no | public | Start date. |
| `end_date` | `date` | yes: project ongoing | public | End date; duration = end - start. |
| `outcome` | `core.text_1000` | yes: not written | public | What the project achieved. |
| `project_url` | `core.text_1000` | yes: no public link | public | Link to the project. |
| `candidate_work_experience_id` | `bigint` | yes: not done for an employer on the profile; set to null if that experience is removed | internal | Job the project was done in. |
| `project_kind_code_type_id` | `bigint` | no | internal | Fixed to code_type PROJECT_KIND; makes the composite FK type-safe. |
| `project_kind_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `PROJECT_KIND`. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

### `prf.candidate_resume`

Resume versions, built in the platform or uploaded.

_lifecycle: soft_delete · row-level security_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key. |
| `candidate_profile_id` | `bigint` | no | internal | Candidate. |
| `version_number` | `core.positive_int` | no | internal | 1, 2, 3 ... per candidate; never reused. |
| `title` | `core.text_255` | no | personal | Candidate's label for the version, e.g. Backend roles. |
| `resume_template_id` | `bigint` | yes: uploaded file, not generated from a template | internal | Template used. |
| `body` | `core.long_text` | yes: uploaded file only | personal | Resume content as entered. |
| `content_language_id` | `bigint` | yes: language not detected | internal | Language of the resume (Rule 7). |
| `file_storage_key` | `core.text_1000` | yes: built in the platform, no file | personal | Object-storage key of the uploaded file. |
| `file_sha256` | `bytea` | yes: no file | internal | SHA-256 of the file; detects duplicate uploads. |
| `file_mime_type` | `core.text_100` | yes: no file | internal | MIME type of the file. |
| `file_size_bytes` | `bigint` | yes: no file | internal | File size, 1 byte to 10 MB. |
| `is_default` | `boolean` | no | internal | Sent with applications by default; at most one live default per candidate. Default false. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |
| `deleted_at` | `timestamp with time zone` | yes: row is live | internal | When the row was soft-deleted (UTC). |
| `deleted_by` | `bigint` | yes: row is live | internal | user_account that soft-deleted the row. |

### `prf.candidate_skill`

Skills a candidate claims.

_lifecycle: hard_delete_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key. |
| `candidate_profile_id` | `bigint` | no | internal | Candidate. |
| `skill_id` | `bigint` | no | public | Skill from the catalogue. |
| `years_of_experience` | `numeric(4,1)` | yes: not stated | public | Years using the skill (0–60). |
| `last_used_year` | `smallint` | yes: not stated or still in use | public | Last year the skill was used. |
| `is_primary` | `boolean` | no | public | Highlighted on the profile. Default false. |
| `proficiency_code_type_id` | `bigint` | no | internal | Fixed to code_type PROFICIENCY_LEVEL; makes the composite FK type-safe. |
| `proficiency_ref_code_id` | `bigint` | yes: not self-assessed yet | internal | Value from mst.ref_code. Enumeration `PROFICIENCY_LEVEL`. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

### `prf.candidate_work_experience`

Employment history.

_lifecycle: hard_delete_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key. |
| `candidate_profile_id` | `bigint` | no | internal | Candidate. |
| `employer_name` | `core.text_255` | no | public | Employer name as entered. |
| `organisation_id` | `bigint` | yes: employer is not an organisation on the platform; set to null if that organisation is removed | internal | Matched employer. |
| `designation` | `core.text_255` | no | public | Job title as entered. |
| `job_role_id` | `bigint` | yes: title not mapped to a standard role yet | public | Standard role. |
| `city_id` | `bigint` | yes: remote or not stated | public | Work location. |
| `start_date` | `date` | no | public | Start date. |
| `end_date` | `date` | yes: current job; see is_current | public | End date. |
| `is_current` | `boolean` | no | public | Current job. Default false. |
| `description` | `core.text_4000` | yes: not written | public | Responsibilities and achievements. |
| `employment_type_code_type_id` | `bigint` | no | internal | Fixed to code_type EMPLOYMENT_TYPE; makes the composite FK type-safe. |
| `employment_type_ref_code_id` | `bigint` | yes: not stated by the candidate | internal | Value from mst.ref_code. Enumeration `EMPLOYMENT_TYPE`. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

### `prf.course`

Courses candidates can enrol in or list.

_lifecycle: deactivate_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | public | Surrogate key. |
| `title` | `core.text_255` | no | public | Course name. |
| `provider_name` | `core.text_255` | no | public | Who runs the course. |
| `course_url` | `core.text_1000` | yes: offline course | public | Course page. |
| `skill_id` | `bigint` | yes: covers several skills | public | Main skill taught. |
| `duration_hours` | `core.positive_int` | yes: self-paced, no stated duration | public | Expected hours. |
| `is_active` | `boolean` | no | public | Open for enrolment. Default true. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

### `prf.profile_completion_rule`

Weight of each profile section in the completion score; active weights total 100.

_lifecycle: deactivate_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key. |
| `weight_percent` | `core.percentage` | no | internal | Contribution of the section to the score. |
| `is_active` | `boolean` | no | internal | Counted in the score. Default true. |
| `profile_section_code_type_id` | `bigint` | no | internal | Fixed to code_type PROFILE_SECTION; makes the composite FK type-safe. |
| `profile_section_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `PROFILE_SECTION`. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

### `prf.profile_view_event`

Every view of a candidate profile by an employer, recruiter or consultant.

_lifecycle: append_only · partitioned_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key (unique with viewed_at). |
| `candidate_profile_id` | `bigint` | no | internal | Profile viewed (the subject). |
| `viewer_user_account_id` | `bigint` | no | internal | Who viewed it (the actor). |
| `viewer_organisation_id` | `bigint` | yes: viewer was not acting for an organisation, e.g. an independent consultant | internal | Organisation the viewer acted for. |
| `viewed_at` | `timestamp with time zone` | no | internal | When it was viewed (UTC); partition key. |
| `view_source_code_type_id` | `bigint` | no | internal | Fixed to code_type VIEW_SOURCE; makes the composite FK type-safe. |
| `view_source_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `VIEW_SOURCE`. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was recorded (UTC). |
| `created_by` | `bigint` | no | internal | user_account that recorded the row. |

### `prf.referral`

Referral codes issued by users and how far each referral progressed. Referral reward events are in the Notifications module.

_lifecycle: soft_delete · row-level security_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key. |
| `referrer_user_account_id` | `bigint` | no | internal | Who referred. |
| `referral_code` | `character varying(16)` | no | public | Code shared with the invitee, 8–16 uppercase letters or digits. |
| `referred_contact_hmac` | `bytea` | yes: open link with no named invitee | personal | Blind index of the invitee's email or phone; the contact itself is not stored. |
| `referred_candidate_profile_id` | `bigint` | yes: invitee has not registered yet | internal | Candidate who registered with the code. |
| `job_requirement_id` | `bigint` | yes: general referral, not for a specific job | internal | Job the referral is for. |
| `invited_at` | `timestamp with time zone` | no | internal | When the code was issued (UTC). |
| `expires_at` | `timestamp with time zone` | no | internal | When the code stops working (UTC). |
| `referral_status_code_type_id` | `bigint` | no | internal | Fixed to code_type REFERRAL_STATUS; makes the composite FK type-safe. |
| `referral_status_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `REFERRAL_STATUS`. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |
| `deleted_at` | `timestamp with time zone` | yes: row is live | internal | When the row was soft-deleted (UTC). |
| `deleted_by` | `bigint` | yes: row is live | internal | user_account that soft-deleted the row. |

### `prf.resume_template`

Layouts the resume builder can render.

_lifecycle: deactivate_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | public | Surrogate key. |
| `template_code` | `core.code` | no | public | Stable code used by the renderer. |
| `english_name` | `core.text_100` | no | public | Name shown in the template picker. |
| `description` | `core.text_1000` | yes: no description written | public | Who the template suits. |
| `is_active` | `boolean` | no | public | Offered for new resumes. Default true. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

## Jobs and Applications (`job`)

### `job.application`

A candidate's application to a job and its current pipeline stage. One per candidate per job. Hash-partitioned by job_requirement_id into 16 partitions.

_lifecycle: soft_delete · partitioned · row-level security_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key (unique with job_requirement_id). |
| `job_requirement_id` | `bigint` | no | internal | Job applied to; partition key. |
| `candidate_profile_id` | `bigint` | no | internal | Candidate. |
| `job_position_id` | `bigint` | yes: applied to the job, location not chosen yet | internal | Position (location) applied for; must belong to the same job. |
| `candidate_resume_id` | `bigint` | yes: applied with the profile only | internal | Resume version sent; must belong to the same candidate. |
| `referral_id` | `bigint` | yes: not a referral | internal | Referral that led to the application. |
| `sourced_by_user_account_id` | `bigint` | yes: candidate applied themselves | internal | Recruiter or consultant who submitted the candidate. |
| `cover_note` | `core.text_4000` | yes: no cover note | personal | Message from the candidate. |
| `applied_at` | `timestamp with time zone` | no | internal | When the application was made (UTC). |
| `status_changed_at` | `timestamp with time zone` | no | internal | When the current status was set (UTC); maintained by trigger. |
| `application_status_code_type_id` | `bigint` | no | internal | Fixed to code_type APPLICATION_STATUS; makes the composite FK type-safe. |
| `application_status_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `APPLICATION_STATUS`. |
| `application_source_code_type_id` | `bigint` | no | internal | Fixed to code_type APPLICATION_SOURCE; makes the composite FK type-safe. |
| `application_source_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `APPLICATION_SOURCE`. |
| `rejection_reason_code_type_id` | `bigint` | no | internal | Fixed to code_type REJECTION_REASON; makes the composite FK type-safe. |
| `rejection_reason_ref_code_id` | `bigint` | yes: application not rejected | internal | Value from mst.ref_code. Enumeration `REJECTION_REASON`. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |
| `deleted_at` | `timestamp with time zone` | yes: row is live | internal | When the row was soft-deleted (UTC). |
| `deleted_by` | `bigint` | yes: row is live | internal | user_account that soft-deleted the row. |

### `job.application_answer`

Screening answers. One row per answer; multiple-choice questions have one row per chosen option.

_lifecycle: append_only · partitioned_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key (unique with job_requirement_id). |
| `application_id` | `bigint` | no | internal | Application. |
| `job_requirement_id` | `bigint` | no | internal | Job; partition key. |
| `questionnaire_question_id` | `bigint` | no | internal | Question answered. |
| `question_option_id` | `bigint` | yes: question is not multiple choice | internal | Chosen option; must belong to the question. |
| `answer_text` | `core.text_4000` | yes: answer is an option, number or date | personal | Free-text answer. |
| `answer_number` | `numeric(18,4)` | yes: answer is not numeric | personal | Numeric answer. |
| `answer_date` | `date` | yes: answer is not a date | personal | Date answer. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was recorded (UTC). |
| `created_by` | `bigint` | no | internal | user_account that recorded the row. |

### `job.application_status_history`

Every pipeline stage change: who, when, from what, to what and why (rejections). The candidate's application history.

_lifecycle: append_only · partitioned_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key (unique with job_requirement_id). |
| `application_id` | `bigint` | no | internal | Application. |
| `job_requirement_id` | `bigint` | no | internal | Job; partition key, co-located with the application. |
| `changed_at` | `timestamp with time zone` | no | internal | When the change took effect (UTC). |
| `from_status_code_type_id` | `bigint` | no | internal | Fixed to code_type APPLICATION_STATUS; makes the composite FK type-safe. |
| `from_status_ref_code_id` | `bigint` | yes: first status of the application | internal | Value from mst.ref_code. Enumeration `APPLICATION_STATUS`. |
| `to_status_code_type_id` | `bigint` | no | internal | Fixed to code_type APPLICATION_STATUS; makes the composite FK type-safe. |
| `to_status_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `APPLICATION_STATUS`. |
| `rejection_reason_code_type_id` | `bigint` | no | internal | Fixed to code_type REJECTION_REASON; makes the composite FK type-safe. |
| `rejection_reason_ref_code_id` | `bigint` | yes: change was not a rejection | internal | Value from mst.ref_code. Enumeration `REJECTION_REASON`. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was recorded (UTC). |
| `created_by` | `bigint` | no | internal | user_account that recorded the row. |

### `job.application_status_transition`

Allowed pipeline moves. A row with no from_status lists a valid initial status.

_lifecycle: hard_delete_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key. |
| `from_status_code_type_id` | `bigint` | no | internal | Fixed to code_type APPLICATION_STATUS; makes the composite FK type-safe. |
| `from_status_ref_code_id` | `bigint` | yes: transition creates a new application (initial status) | internal | Value from mst.ref_code. Enumeration `APPLICATION_STATUS`. |
| `to_status_code_type_id` | `bigint` | no | internal | Fixed to code_type APPLICATION_STATUS; makes the composite FK type-safe. |
| `to_status_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `APPLICATION_STATUS`. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

### `job.interview`

Interview rounds for an application.

_lifecycle: soft_delete · row-level security_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key. |
| `application_id` | `bigint` | no | internal | Application. |
| `job_requirement_id` | `bigint` | no | internal | Job (with application_id, references the partitioned application). |
| `round_number` | `core.positive_int` | no | internal | 1 for the first round, 2 for the second ... |
| `scheduled_start_at` | `timestamp with time zone` | no | internal | Start (UTC). |
| `scheduled_end_at` | `timestamp with time zone` | no | internal | End (UTC); after the start. |
| `interviewer_user_account_id` | `bigint` | yes: interviewer not assigned yet | internal | Lead interviewer; cannot be double-booked. |
| `feedback` | `core.text_4000` | yes: no feedback recorded yet | personal | Interviewer feedback. |
| `rating` | `smallint` | yes: not rated yet | personal | Rating 1–5. |
| `interview_mode_code_type_id` | `bigint` | no | internal | Fixed to code_type INTERVIEW_MODE; makes the composite FK type-safe. |
| `interview_mode_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `INTERVIEW_MODE`. |
| `interview_outcome_code_type_id` | `bigint` | no | internal | Fixed to code_type INTERVIEW_OUTCOME; makes the composite FK type-safe. |
| `interview_outcome_ref_code_id` | `bigint` | yes: interview not held yet | internal | Value from mst.ref_code. Enumeration `INTERVIEW_OUTCOME`. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |
| `deleted_at` | `timestamp with time zone` | yes: row is live | internal | When the row was soft-deleted (UTC). |
| `deleted_by` | `bigint` | yes: row is live | internal | user_account that soft-deleted the row. |

### `job.job_position`

Openings of a job per location. filled_count is maintained when candidates join and can never exceed openings_count.

_lifecycle: hard_delete_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key. |
| `job_requirement_id` | `bigint` | no | internal | Job. |
| `city_id` | `bigint` | yes: remote position, no fixed location | public | Work location. |
| `openings_count` | `core.positive_int` | no | public | Number of people to hire at this location (> 0). |
| `filled_count` | `core.non_negative_int` | no | internal | Candidates who have joined. Default 0. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

### `job.job_requirement`

A job post by an employer: requirements, salary, publish state and consultant openness.

_lifecycle: soft_delete · row-level security_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key. |
| `public_id` | `uuid` | no | public | Identifier used in URLs and APIs. |
| `organisation_id` | `bigint` | no | internal | Employer or client the job belongs to; recruiters only see their own organisation's jobs. |
| `posted_by_user_account_id` | `bigint` | no | internal | Who created the post. |
| `title` | `core.text_255` | no | public | Job title. |
| `job_role_id` | `bigint` | yes: title not mapped to a standard role yet | public | Standard role. |
| `industry_id` | `bigint` | yes: employer did not classify the job | public | Industry. |
| `description` | `core.long_text` | no | public | Full description as entered. |
| `description_language_id` | `bigint` | yes: language not detected | internal | Language of the description (Rule 7). |
| `min_experience_months` | `core.non_negative_int` | no | public | Minimum experience; 0 for freshers. Default 0. |
| `max_experience_months` | `core.non_negative_int` | yes: no upper limit | public | Maximum experience. |
| `salary_currency_id` | `bigint` | yes: salary not disclosed | public | Currency of the salary range. |
| `salary_min_amount` | `core.money_amount` | yes: salary not disclosed; see salary_disclosure | public | Lower bound of the salary range. |
| `salary_max_amount` | `core.money_amount` | yes: not disclosed, or no upper bound stated | public | Upper bound of the salary range. |
| `is_open_to_consultants` | `boolean` | no | internal | Consultants may source candidates for this job. Default false. |
| `published_at` | `timestamp with time zone` | yes: never published (draft or pending approval) | public | First publish time (UTC). |
| `expires_at` | `timestamp with time zone` | yes: no expiry set | public | When the post stops accepting applications (UTC). |
| `closed_at` | `timestamp with time zone` | yes: not closed | internal | When the employer closed the job (UTC). |
| `source_record_id` | `core.text_100` | yes: posted directly on the platform | internal | Record id in the legacy system. |
| `search_document` | `tsvector` | no | public | Full-text search vector over title (weight A) and description (weight B); generated, language-neutral 'simple' configuration for multilingual text. |
| `job_category_code_type_id` | `bigint` | no | internal | Fixed to code_type JOB_CATEGORY; makes the composite FK type-safe. |
| `job_category_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `JOB_CATEGORY`. |
| `employment_type_code_type_id` | `bigint` | no | internal | Fixed to code_type EMPLOYMENT_TYPE; makes the composite FK type-safe. |
| `employment_type_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `EMPLOYMENT_TYPE`. |
| `work_type_code_type_id` | `bigint` | no | internal | Fixed to code_type WORK_TYPE; makes the composite FK type-safe. |
| `work_type_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `WORK_TYPE`. |
| `salary_disclosure_code_type_id` | `bigint` | no | internal | Fixed to code_type DISCLOSURE_STATUS; makes the composite FK type-safe. |
| `salary_disclosure_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `DISCLOSURE_STATUS`. |
| `salary_period_code_type_id` | `bigint` | no | internal | Fixed to code_type SALARY_PERIOD; makes the composite FK type-safe. |
| `salary_period_ref_code_id` | `bigint` | yes: salary not disclosed | internal | Value from mst.ref_code. Enumeration `SALARY_PERIOD`. |
| `publish_status_code_type_id` | `bigint` | no | internal | Fixed to code_type JOB_PUBLISH_STATUS; makes the composite FK type-safe. |
| `publish_status_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `JOB_PUBLISH_STATUS`. |
| `source_system_code_type_id` | `bigint` | no | internal | Fixed to code_type SOURCE_SYSTEM; makes the composite FK type-safe. |
| `source_system_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `SOURCE_SYSTEM`. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |
| `deleted_at` | `timestamp with time zone` | yes: row is live | internal | When the row was soft-deleted (UTC). |
| `deleted_by` | `bigint` | yes: row is live | internal | user_account that soft-deleted the row. |

### `job.job_requirement_qualification`

Qualifications a job asks for.

_lifecycle: hard_delete_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key. |
| `job_requirement_id` | `bigint` | no | internal | Job. |
| `qualification_id` | `bigint` | no | public | Qualification required. |
| `is_mandatory` | `boolean` | no | public | Must-have. Default true. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

### `job.job_requirement_questionnaire`

Questionnaires attached to a job.

_lifecycle: hard_delete_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key. |
| `job_requirement_id` | `bigint` | no | internal | Job. |
| `questionnaire_id` | `bigint` | no | internal | Questionnaire candidates must answer. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

### `job.job_requirement_skill`

Skills a job asks for.

_lifecycle: hard_delete_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key. |
| `job_requirement_id` | `bigint` | no | internal | Job. |
| `skill_id` | `bigint` | no | public | Skill required. |
| `is_mandatory` | `boolean` | no | public | Must-have rather than nice-to-have. Default true. |
| `min_years` | `numeric(4,1)` | yes: no minimum stated | public | Minimum years with the skill. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

### `job.job_search_event`

Candidate job-search history, one row per search, with the main filters as columns (feeds job alerts and trending-job analytics).

_lifecycle: append_only · partitioned_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key (unique with searched_at). |
| `user_account_id` | `bigint` | yes: guest search without an account | internal | Who searched. |
| `candidate_profile_id` | `bigint` | yes: searcher has no candidate profile, e.g. guest | internal | Candidate who searched. |
| `search_text` | `core.text_255` | yes: filter-only search | internal | Keywords typed. |
| `city_id` | `bigint` | yes: no location filter | internal | Location filter. |
| `skill_id` | `bigint` | yes: no skill filter | internal | Skill filter. |
| `job_role_id` | `bigint` | yes: no role filter | internal | Role filter. |
| `min_salary_amount` | `core.money_amount` | yes: no salary filter | internal | Minimum salary filter. |
| `salary_currency_id` | `bigint` | yes: no salary filter | internal | Currency of the salary filter. |
| `results_count` | `core.non_negative_int` | no | internal | Number of jobs returned. |
| `searched_at` | `timestamp with time zone` | no | internal | When the search ran (UTC); partition key. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was recorded (UTC). |
| `created_by` | `bigint` | no | internal | user_account that recorded the row. |

### `job.job_shortlist_entry`

Candidates shortlisted for a job, whether or not they applied. One live entry per candidate per job.

_lifecycle: soft_delete · row-level security_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key. |
| `job_requirement_id` | `bigint` | no | internal | Job. |
| `candidate_profile_id` | `bigint` | no | internal | Candidate. |
| `shortlisted_by_user_account_id` | `bigint` | no | internal | Recruiter, employer or consultant who shortlisted. |
| `application_id` | `bigint` | yes: candidate has not applied, e.g. sourced from search | internal | Matching application. |
| `note` | `core.text_1000` | yes: no note | internal | Reviewer note. |
| `shortlist_source_code_type_id` | `bigint` | no | internal | Fixed to code_type SHORTLIST_SOURCE; makes the composite FK type-safe. |
| `shortlist_source_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `SHORTLIST_SOURCE`. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |
| `deleted_at` | `timestamp with time zone` | yes: row is live | internal | When the row was soft-deleted (UTC). |
| `deleted_by` | `bigint` | yes: row is live | internal | user_account that soft-deleted the row. |

### `job.job_shortlist_event`

Shortlist history for employers and recruiters, written by trigger.

_lifecycle: append_only_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key. |
| `job_shortlist_entry_id` | `bigint` | no | internal | Shortlist entry that changed. |
| `shortlist_action_code_type_id` | `bigint` | no | internal | Fixed to code_type BOOKMARK_ACTION; makes the composite FK type-safe. |
| `shortlist_action_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `BOOKMARK_ACTION`. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was recorded (UTC). |
| `created_by` | `bigint` | no | internal | user_account that recorded the row. |

### `job.joining`

Whether an accepted offer became a hire. Joining fills a position; a position can never be filled beyond its openings.

_lifecycle: hard_delete_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key. |
| `application_id` | `bigint` | no | internal | Application. |
| `job_requirement_id` | `bigint` | no | internal | Job (with application_id, references the partitioned application). |
| `offer_id` | `bigint` | no | internal | Accepted offer; must belong to the same application. |
| `joined_on` | `date` | yes: candidate has not joined (deferred or no-show) | internal | First working day. |
| `joining_status_code_type_id` | `bigint` | no | internal | Fixed to code_type JOINING_STATUS; makes the composite FK type-safe. |
| `joining_status_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `JOINING_STATUS`. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

### `job.offer`

Offers made on an application; a revised offer is a new version.

_lifecycle: soft_delete · row-level security_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key. |
| `application_id` | `bigint` | no | internal | Application. |
| `job_requirement_id` | `bigint` | no | internal | Job (with application_id, references the partitioned application). |
| `offer_version` | `core.positive_int` | no | internal | 1 for the first offer, 2 for a revision ... |
| `offered_amount` | `core.money_amount` | no | personal | Offered salary for salary_period. |
| `currency_id` | `bigint` | no | personal | Currency of offered_amount. |
| `extended_at` | `timestamp with time zone` | no | internal | When the offer was made (UTC). |
| `valid_until` | `date` | no | internal | Last day the candidate can accept. |
| `responded_at` | `timestamp with time zone` | yes: no response yet, or offer withdrawn or expired | internal | When the candidate accepted or declined (UTC). |
| `expected_joining_date` | `date` | yes: to be agreed | internal | Planned start date. |
| `letter_storage_key` | `core.text_1000` | yes: letter not generated yet | personal | Object-storage key of the offer letter. |
| `salary_period_code_type_id` | `bigint` | no | internal | Fixed to code_type SALARY_PERIOD; makes the composite FK type-safe. |
| `salary_period_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `SALARY_PERIOD`. |
| `offer_status_code_type_id` | `bigint` | no | internal | Fixed to code_type OFFER_STATUS; makes the composite FK type-safe. |
| `offer_status_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `OFFER_STATUS`. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |
| `deleted_at` | `timestamp with time zone` | yes: row is live | internal | When the row was soft-deleted (UTC). |
| `deleted_by` | `bigint` | yes: row is live | internal | user_account that soft-deleted the row. |

### `job.question_option`

Choices for single- and multiple-choice questions.

_lifecycle: hard_delete_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key. |
| `questionnaire_question_id` | `bigint` | no | internal | Question. |
| `sequence_no` | `core.positive_int` | no | internal | Display order. |
| `option_text` | `core.text_255` | no | public | Choice text. |
| `is_knockout` | `boolean` | no | internal | Choosing it disqualifies the application automatically. Default false. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

### `job.questionnaire`

Reusable screening questionnaire owned by an employer.

_lifecycle: deactivate_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key. |
| `organisation_id` | `bigint` | no | internal | Owning employer. |
| `title` | `core.text_255` | no | internal | Name shown to the employer. |
| `description` | `core.text_1000` | yes: no instructions | public | Instructions shown to candidates. |
| `is_active` | `boolean` | no | internal | Can be attached to new jobs. Default true. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

### `job.questionnaire_question`

Questions in a questionnaire, in display order.

_lifecycle: hard_delete_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key. |
| `questionnaire_id` | `bigint` | no | internal | Questionnaire. |
| `sequence_no` | `core.positive_int` | no | internal | Display order (1, 2, 3 ...). |
| `question_text` | `core.text_1000` | no | public | Question as written by the employer. |
| `is_mandatory` | `boolean` | no | public | Must be answered to apply. Default true. |
| `answer_type_code_type_id` | `bigint` | no | internal | Fixed to code_type ANSWER_TYPE; makes the composite FK type-safe. |
| `answer_type_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `ANSWER_TYPE`. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |

## Administration (`adm`)

### `adm.user_account`

Anyone who can act on the platform. Credentials, roles and consent are attached by the Administration module.

_lifecycle: soft_delete · row-level security_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key. Never exposed outside the platform. |
| `public_id` | `uuid` | no | internal | Identifier used in URLs and APIs. |
| `preferred_language_id` | `bigint` | no | internal | UI language. |
| `last_login_at` | `timestamp with time zone` | yes: account has never signed in | internal | Most recent successful sign-in (UTC). |
| `user_type_code_type_id` | `bigint` | no | internal | Fixed to code_type USER_TYPE; makes the composite FK type-safe. |
| `user_type_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `USER_TYPE`. |
| `account_status_code_type_id` | `bigint` | no | internal | Fixed to code_type ACCOUNT_STATUS; makes the composite FK type-safe. |
| `account_status_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `ACCOUNT_STATUS`. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |
| `deleted_at` | `timestamp with time zone` | yes: row is live | internal | When the row was soft-deleted (UTC). |
| `deleted_by` | `bigint` | yes: row is live | internal | user_account that soft-deleted the row. |

## Organisation and account (`org`)

### `org.organisation`

Employers, clients, consultancies and institutions. Hierarchy, locations, tax identifiers and verification are added by the Organisation module.

_lifecycle: soft_delete · row-level security_

| Column | Type / domain | Null | Class | Description |
| --- | --- | --- | --- | --- |
| `id` | `bigint` | no | internal | Surrogate key. |
| `public_id` | `uuid` | no | public | Identifier used in URLs and APIs. |
| `legal_name` | `core.text_255` | no | public | Registered legal name. |
| `display_name` | `core.text_255` | no | public | Name shown on job posts. |
| `country_id` | `bigint` | no | public | Country of registration. |
| `organisation_type_code_type_id` | `bigint` | no | internal | Fixed to code_type ORGANISATION_TYPE; makes the composite FK type-safe. |
| `organisation_type_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `ORGANISATION_TYPE`. |
| `account_status_code_type_id` | `bigint` | no | internal | Fixed to code_type ACCOUNT_STATUS; makes the composite FK type-safe. |
| `account_status_ref_code_id` | `bigint` | no | internal | Value from mst.ref_code. Enumeration `ACCOUNT_STATUS`. |
| `created_at` | `timestamp with time zone` | no | internal | When the row was created (UTC). |
| `created_by` | `bigint` | no | internal | user_account that created the row. |
| `updated_at` | `timestamp with time zone` | no | internal | When the row was last changed (UTC). |
| `updated_by` | `bigint` | no | internal | user_account that last changed the row. |
| `deleted_at` | `timestamp with time zone` | yes: row is live | internal | When the row was soft-deleted (UTC). |
| `deleted_by` | `bigint` | yes: row is live | internal | user_account that soft-deleted the row. |
