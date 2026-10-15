"""Cross-platform task runner (works on Windows, macOS and Linux; no make or bash needed).

    python run.py check      rebuild the database from zero, lint it, run the tests
    python run.py seed       load synthetic data (add: small | medium | laptop)
    python run.py demo       live demo of the database refusing rule violations
    python run.py reset      rebuild the database only
    python run.py lint       schema compliance linter only
    python run.py test       rule-violation tests only
    python run.py docs       regenerate the data dictionary and ER diagram

Connection settings come from the standard PostgreSQL variables, with these defaults:
    PGHOST=localhost PGPORT=5432 PGUSER=postgres PGPASSWORD=postgres PGDATABASE=talentra
Requires psql on the PATH (installed with PostgreSQL) and: pip install -r requirements.txt
"""
import glob
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ENV = dict(os.environ)
for key, default in (("PGHOST", "localhost"), ("PGPORT", "5432"), ("PGUSER", "postgres"),
                     ("PGPASSWORD", "postgres"), ("PGDATABASE", "talentra")):
    ENV.setdefault(key, default)
ENV.setdefault("TALENTRA_DSN", "host={PGHOST} port={PGPORT} user={PGUSER} password={PGPASSWORD} dbname={PGDATABASE}".format(**ENV))
ENV["PYTHONIOENCODING"] = "utf-8"
ENV["PGCLIENTENCODING"] = "UTF8"


def find_psql():
    """psql on PATH, or the standard Windows install folders (so PATH never needs editing)."""
    found = shutil.which("psql")
    if found:
        return found
    for version in ("18", "17", "16", "15"):
        candidate = Path(f"C:/Program Files/PostgreSQL/{version}/bin/psql.exe")
        if candidate.exists():
            return str(candidate)
    return None


PSQL = find_psql()


def psql(*args, database=None, options=None, check=True):
    if not PSQL:
        sys.exit("PostgreSQL was not found. Install PostgreSQL 16 (see SETUP.md), then run this again.")
    env = dict(ENV)
    if database:
        env["PGDATABASE"] = database
    if options:
        env["PGOPTIONS"] = options
    result = subprocess.run([PSQL, "--no-psqlrc", "--quiet", *args], cwd=ROOT, env=env)
    if check and result.returncode != 0:
        sys.exit(result.returncode)
    return result.returncode


def reset():
    db = ENV["PGDATABASE"]
    psql("-c", f"DROP DATABASE IF EXISTS {db} WITH (FORCE)", database="postgres")
    psql("-c", f"CREATE DATABASE {db} ENCODING 'UTF8' TEMPLATE template0", database="postgres")
    for file in sorted(glob.glob(str(ROOT / "migrations" / "*.sql"))):
        print(f"{Path(file).name:55s}", end="", flush=True)
        psql("--set", "ON_ERROR_STOP=1", "--single-transaction", "--file", file, "--output", os.devnull,
             options="-c app.user_id=1 -c client_min_messages=warning")
        print("ok")


def lint():
    psql("--set", "ON_ERROR_STOP=1", "--file", str(ROOT / "tools" / "lint_schema.sql"))


def test():
    code = subprocess.run([sys.executable, "-m", "pytest", "-q", "tests"], cwd=ROOT, env=ENV).returncode
    if code:
        sys.exit(code)


def seed(scale="small"):
    code = subprocess.run([sys.executable, "-m", "generator", "--scale", scale], cwd=ROOT, env=ENV).returncode
    if code:
        sys.exit(code)


def demo():
    psql("--file", str(ROOT / "demo" / "demo.sql"), check=False)


def docs():
    (ROOT / "docs" / "generated").mkdir(parents=True, exist_ok=True)
    for script, out in (("data_dictionary.py", "data_dictionary.md"), ("er_diagram.py", "er_phase1.md")):
        with open(ROOT / "docs" / "generated" / out, "w", encoding="utf-8") as f:
            subprocess.run([sys.executable, str(ROOT / "tools" / script)], cwd=ROOT, env=ENV, stdout=f, check=True)
        print(f"Wrote docs/generated/{out}")


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "help"
    if command == "check":
        reset(); lint(); test(); print("All checks passed.")
    elif command == "reset":
        reset()
    elif command == "lint":
        lint()
    elif command == "test":
        test()
    elif command == "seed":
        seed(sys.argv[2] if len(sys.argv) > 2 else "small")
    elif command == "demo":
        demo()
    elif command == "docs":
        docs()
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
