# Contributing

Thank you for helping. Bethesda PACS runs in a real clinic, together with Bethesda EMR, so
changes are judged first by whether an existing install keeps working after an update: the
same `.env`, the same image store, the same devices.

## Run it

```sh
./setup.sh          # Linux / macOS / NAS   (Windows: .\setup.ps1, or double-click start.bat)
```

`setup` writes a `.env` with a random Orthanc password and bridge token on first run and
starts Orthanc and the worklist bridge with Docker Compose. Orthanc's own pages are then at
http://localhost:9090 (user `admin`, password in `.env`). Never commit `.env`;
`.env.example` lists what it can hold. The EMR is a separate repository
(Bethesda EMR); the bridge reads its order feed.

## Work on an isolated stack

Do not run development code or tests against the stack named `bethesda-pacs` - on a clinic
server that is the live PACS, with the real images and the ports the devices use (9090,
4242). `docker-compose.session.yml` gives a session its own containers, named volumes,
image tag and ports bound to 127.0.0.1:

```sh
docker compose -p bethesda-s-mywork-pacs --env-file test.env \
  -f docker-compose.yml -f docker-compose.session.yml up -d --build
# ... work, test ...
docker compose -p bethesda-s-mywork-pacs -f docker-compose.yml -f docker-compose.session.yml down -v
```

`test.env` holds throwaway values (`ORTHANC_PASSWORD`, `BRIDGE_TOKEN`), never the clinic's
`.env`. The bridge joins an EMR session stack's network (`SESSION_EMR_NETWORK`); start that
EMR stack first - see the top of `docker-compose.session.yml`.

## Test

- Bridge: `python -m py_compile bridge/*.py`, then on the isolated stack place an imaging
  order in the test EMR and check that a `.wl` file appears and that `q_test.py` lists it
  (copy it into the session's bridge container with `docker cp`, `pip install pynetdicom`
  there, then `python q_test.py`). `make_demo.py` / `storetest.py` send made-up images;
  see **Test tools** in `README.md`.
- `docker compose config` with a test `.env` must succeed, and must fail without
  `ORTHANC_PASSWORD`.
- Bethesda CD: `bethesda-cd\build.ps1`, then the scripts in `bethesda-cd\tests` (they say at
  their top what they need; the ones that talk to an EMR use a test EMR and the password in
  `BETHESDA_CD_TEST_PASSWORD`).

## Commits

- One subject line saying what changed for the user or the operator, then a short body with
  the why when it is not obvious.
- Add a `CHANGELOG.md` entry for each release (and `bethesda-cd/CHANGELOG.md` plus
  `bethesda-cd/src/shared/Version.cs` for a new Bethesda CD), with what to do after updating.
- Keep the Orthanc image tag pinned; change it only on purpose, after trying the existing
  image store on an isolated stack.
- Screen texts of the Windows tools come in French, Korean and English; a new one goes into
  all three.
- No real patient data, clinic data, device names, addresses, passwords or tokens in code,
  tests, docs or commits.

By contributing you agree that your contribution is licensed under GPL-3.0 (see `LICENSE`).
