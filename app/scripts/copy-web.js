// Copies the game from the website (../index.html and friends) into www/ for the phone app.
const fs = require('fs'), path = require('path');
const root = path.join(__dirname, '..', '..'), www = path.join(__dirname, '..', 'www');
fs.rmSync(www, {recursive: true, force: true});
fs.mkdirSync(www, {recursive: true});
for (const f of ['index.html', 'icon.png', 'manifest.json', 'og.png']) fs.copyFileSync(path.join(root, f), path.join(www, f));
console.log('Copied the game into app/www');
