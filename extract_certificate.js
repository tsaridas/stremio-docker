const fs = require('fs'); 
args = process.argv;
if (args[2] === undefined ) {
	console.log("Provide the folder path of stremio config root.");
	process.exit(1);
}
const config = require(args[2] + '/httpsCert.json');
const fullCert = config.key + config.cert;
fs.writeFile(args[2]+config.domain+'.pem', fullCert, (err) => {
    if (err) {
      console.log('Failed to write updated data to file');
      process.exit(1);
    }
});
console.log(config.domain);
