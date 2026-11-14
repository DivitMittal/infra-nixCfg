# Home Directory

Home-manager module catalog defining the user-level environment, organized by domain and shared across every host in the fleet.

## Structure

```
home/
├── comms/        # Email, IRC, RSS
├── dev/          # Development (JS, Python, cloud)
├── gui/          # GUI apps, desktop managers
├── media/        # Media players
├── tools/        # Utilities, productivity
├── tty/          # Terminal tools (shells, editors, multiplexers, VCS)
└── web/          # Browsers
```

## Usage

Platform-specific subdirs (e.g., `gui/darwin/`, `gui/linux/`).
Auto-imported via `scanPaths`.
Host-specific overrides: `hosts/HOSTNAME/home/`

## Rebuild

```bash
hms   # Rebuild home config
hmst  # Rebuild with traces
```
