-include .env

# updates vscode settings to detect our foundry remappings
update-remappings:
	node .vscode/update-remappings.js

