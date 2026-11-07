# Security policy

Earshot records audio: conversations around you and whatever your iPhone plays. Bugs that expose
that audio, its transcripts or summaries are security bugs, for example:

- audio stored while 待命模式 (standby) is not armed;
- recordings or transcripts written anywhere other than the App Group container, the iCloud folder
  you picked, or the configured Mac output folder;
- credentials (for your transcription service) reaching logs, command arguments or the repository;
- any network access by the iPhone app or its extensions (they have none by design).

Report privately through GitHub's **Report a vulnerability** button on the Security tab, not in a
public issue. Include versions and a synthetic reproduction — never a real recording. Expect a first
reply within a week.

Supported: the latest release on `main`.
