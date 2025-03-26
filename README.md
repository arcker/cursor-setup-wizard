# Cursor Setup Wizard

A simple and user-friendly setup wizard for installing and configuring Cursor on Ubuntu and its derivatives.

## Features

- 🚀 One-click installation of Cursor
- 🔄 Automatic version checking and updates
- 🎨 Beautiful and intuitive interface
- 🔒 Secure AppArmor profile configuration
- 🖥️ Desktop launcher creation
- ⌨️ CLI command integration
- 🔄 Backup and restore functionality
- 🛠️ Easy reconfiguration options

## Quick Install (Ubuntu/Debian)

Pour installer Cursor en une seule commande, copiez et collez cette ligne dans votre terminal :

```bash
curl -s https://raw.githubusercontent.com/arcker/cursor-setup-wizard/main/cursor_setup.sh | bash
```

Cette commande va :
1. Télécharger le script
2. L'exécuter directement
3. Afficher le menu d'installation

## Manual Installation

1. Clone the repository:
```bash
git clone https://github.com/arcker/cursor-setup-wizard.git
cd cursor-setup-wizard
```

2. Make the script executable:
```bash
chmod +x cursor_setup.sh
```

3. Run the script:
```bash
./cursor_setup.sh
```

## Usage

The script provides several options:

- `--install`: Direct installation without menu
- `--restore`: Restore from a previous backup
- `--verbose`: Show detailed output

## Requirements

- Ubuntu or Ubuntu-based distribution
- Internet connection
- Sudo privileges
- At least 500MB of free disk space
- At least 2GB of available RAM

## Credits

This is an improved fork of the original script by [jorcelinojunior](https://github.com/jorcelinojunior/cursor-setup-wizard).
Modified and enhanced by [Arcker](https://github.com/arcker).

Enjoyed this improved version? Support the fork author!
[☕ Buy Arcker a coffee](https://buymeacoffee.com/arcker)

Want to support the original author?
[☕ Buy jorcelinojunior a coffee](https://buymeacoffee.com/jorcelinojunior)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details. 