const fs = require("fs");
const path = require("path");

const remappingsFile = path.join(__dirname, "..", "remappings.txt");
const vscodeSettingsFile = path.join(__dirname, "settings.json");

const remappings = fs
  .readFileSync(remappingsFile, "utf-8")
  .split("\n")
  .filter(Boolean);

const settings = {
  "solidity.packageDefaultDependenciesContractsDirectory": "src",
  "solidity.packageDefaultDependenciesDirectory": "lib",
  "solidity.remappings": remappings
};

fs.writeFileSync(vscodeSettingsFile, JSON.stringify(settings, null, 2));
console.log("✅ VSCode remappings updated!");
