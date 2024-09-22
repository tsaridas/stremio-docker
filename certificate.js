const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// Usage examples:
// Load certificate:
// node certificate.js --action load --pem-path /path/to/certificate.pem --domain example.com --json-path /path/to/output.json
//
// Extract certificate:
// node certificate.js --action extract --json-path /path/to/input.json

function parseCommandLineArgs() {
    const args = process.argv.slice(2);
    const parsedArgs = {};

    for (let i = 0; i < args.length; i += 2) {
        const key = args[i].replace('--', '');
        const value = args[i + 1];
        parsedArgs[key] = value;
    }

    if (!parsedArgs.action || (parsedArgs.action === 'load' && (!parsedArgs['pem-path'] || !parsedArgs.domain || !parsedArgs['json-path'])) || (parsedArgs.action === 'extract' && !parsedArgs['json-path'])) {
        console.error('Usage: node certificate.js --action <load|extract> [--pem-path <path_to_pem_file> --domain <domain_name>] --json-path <path_to_json_file>');
        process.exit(1);
    }

    return parsedArgs;
}

function loadCertificate(pemPath, domain, jsonPath) {
    try {
        const pemContent = fs.readFileSync(pemPath, 'utf8');
        const [privateKey, certificate] = pemContent.split('-----END PRIVATE KEY-----');

        const cert = new crypto.X509Certificate(certificate);
        const notBefore = cert.validFrom;
        const notAfter = cert.validTo;

        const httpsCertContent = {
            domain: domain,
            key: privateKey.trim() + '\n-----END PRIVATE KEY-----\n',
            cert: certificate.trim(),
            notBefore: new Date(notBefore).toISOString(),
            notAfter: new Date(notAfter).toISOString()
        };

        fs.writeFileSync(jsonPath, JSON.stringify(httpsCertContent, null, 2));

        console.log(`Certificate information saved to ${jsonPath}`);
    } catch (error) {
        console.error(`Error loading certificate: ${error.message}`);
        process.exit(1);
    }
}

function extractCertificate(jsonPath) {
    try {
        const jsonContent = fs.readFileSync(jsonPath, 'utf8');
        const certData = JSON.parse(jsonContent);

        const pemContent = `${certData.key}\n${certData.cert}`;
        const outputPath = path.join(path.dirname(jsonPath), `${certData.domain}.pem`);
        fs.writeFileSync(outputPath, pemContent);

        console.log(`${certData.domain}`);
    } catch (error) {
        console.error(`Error extracting certificate: ${error.message}`);
        process.exit(1);
    }
}

const args = parseCommandLineArgs();

try {
    if (args.action === 'load') {
        loadCertificate(args['pem-path'], args.domain, args['json-path']);
    } else if (args.action === 'extract') {
        extractCertificate(args['json-path']);
    } else {
        throw new Error('Invalid action specified');
    }
} catch (error) {
    console.error(`Error: ${error.message}`);
    process.exit(1);
}
