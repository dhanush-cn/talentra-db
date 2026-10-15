# Laptop setup

About 15 minutes the first time. You need PostgreSQL 16 (with `psql`), Python 3.11+ and this folder.

## Windows

1. **Install PostgreSQL 16** from https://www.postgresql.org/download/windows/ (EDB installer).
   - Password for the `postgres` user: `postgres` (or your own; see step 5).
   - Port: `5432`. Keep "Command Line Tools" ticked. Skip Stack Builder.
2. **Add psql to PATH:** Start → "Edit the system environment variables" → Environment Variables → Path → New →
   `C:\Program Files\PostgreSQL\16\bin`. Close and reopen VS Code and terminals.
3. **Check:** in a new terminal, `psql --version` and `python --version` both print a version.
4. **Open the project:** unzip `talentra-db.zip`, open the `talentra-db` folder in VS Code, open a terminal (Ctrl + `).
5. **Install Python packages:** `pip install -r requirements.txt`
   If your postgres password is not `postgres`: `$env:PGPASSWORD = "yourpassword"` (PowerShell) in the same terminal.
6. **For Kannada and Hindi text in the terminal:** run `chcp 65001` once per terminal.
7. **Run:**
   ```
   python run.py check     # builds 55 tables, lint 0 errors, 86 tests pass
   python run.py seed      # 10,000 candidates, 1,000 jobs, 50,000 applications (~30 s)
   python run.py demo      # the database refusing 11 rule violations
   ```

## macOS

```bash
brew install postgresql@16 && brew services start postgresql@16
echo 'export PATH="/opt/homebrew/opt/postgresql@16/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
export PGUSER=$(whoami) PGPASSWORD=           # Homebrew's superuser is your login name
pip3 install -r requirements.txt
python3 run.py check && python3 run.py seed && python3 run.py demo
```

## With Docker instead (any OS, Docker Desktop running)

```bash
docker compose up -d        # PostgreSQL 16 on port 5432, password postgres
python run.py check
```
You still need `psql` on PATH (install PostgreSQL's command line tools, or use `docker exec -it talentra-db psql -U postgres talentra` for a session).

## If something fails

| Message | Fix |
| --- | --- |
| `psql was not found` | Step 2: add PostgreSQL's `bin` folder to PATH, reopen the terminal |
| `password authentication failed` | Set `PGPASSWORD` to the password you chose at install |
| `connection refused` | PostgreSQL is not running: Windows → Services → start `postgresql-x64-16`; macOS → `brew services start postgresql@16` |
| `database "talentra" is being accessed by other users` | Close other psql or VS Code database connections, then rerun |
| Boxes instead of Kannada/Hindi letters | `chcp 65001`, or use Windows Terminal |
