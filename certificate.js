const fs = require('fs');
const process = require('process');
const path = require('path');
const crypto = require('crypto');
// Usage examples:
// Load certificate:
// node certificate.js --action load --pem-path /path/to/certificate.pem --domain example.com --json-path /path/to/output.json
//
// Extract certificate:
// node certificate.js --action extract --json-path /path/to/input.json
//
// Fetch certificate:
// node certificate.js --action fetch

async function getCertificate() {
  try {
    let ipAddress = process.env.IPADDRESS;

    if (ipAddress === "0-0-0-0") {
        const publicIp = await fetch('https://api.ipify.org?format=json').then(res => res.json()).then(data => data.ip);
        ipAddress = publicIp;
    }

    if (!/^(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}$/.test(ipAddress)) {
        throw new Error('Invalid IPv4 address format.');
    }

    let data;
    let attempts = 0;
    const maxAttempts = Number(process.env.MAXATTEMPTS) || 5;
    while (attempts < maxAttempts) {
        try {
            const response = await fetch('http://api.strem.io/api/certificateGet', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    authKey: null,
                    ipAddress: ipAddress,
                }),
            });
            if (!response || !response.ok) {
                throw new Error(`Failed to fetch certificate.`);
            }

            data = await response.json();
            break;
        } catch (error) {
            console.error(`Failed to fetch certificate. Retrying... (${attempts + 1}/${maxAttempts})`);
            attempts++;
            if (attempts === maxAttempts) {
                throw new Error(`Failed to fetch certificate after ${maxAttempts} attempts.`);
            }
            await new Promise(resolve => setTimeout(resolve, 500));
        }
    }

    if (!data) {
        throw new Error('No data received from certificate API after retries.');
    }

    if (!data.result || !data.result.certificate) {
        throw new Error('No certificate found in API response.');
    }

    const certResp = JSON.parse(data.result.certificate);

    if (!certResp) {
        throw new Error('Missing certificate or privateKey in API response.');
    }

    if (!certResp.contents || !certResp.contents.Certificate || !certResp.contents.PrivateKey) {
        throw new Error('Certificate or PrivateKey missing in API response.');
    }

    const combinedCertificates = Buffer.from(certResp.contents.Certificate, 'base64').toString() + '\n' + Buffer.from(certResp.contents.PrivateKey, 'base64').toString();

    fs.writeFileSync('certificates.pem', combinedCertificates);

    console.log(`Certificates saved successfully! Setup an A record for ${ipAddress} to point to ${ipAddress.replace(/\./g, '-')}.519b6502d940.stremio.rocks`)
  } catch (error) {
    console.error('Error fetching certificate:', error);
  }
}

function parseCommandLineArgs() {
    const args = process.argv.slice(2);
    const parsedArgs = {};

    for (let i = 0; i < args.length; i += 2) {
        const key = args[i].replace('--', '');
        const value = args[i + 1];
        parsedArgs[key] = value;
    }

    if (!parsedArgs.action || (parsedArgs.action === 'load' && (!parsedArgs['pem-path'] || !parsedArgs.domain || !parsedArgs['json-path'])) || (parsedArgs.action === 'extract' && !parsedArgs['json-path']) || (parsedArgs.action === 'fetch' && Object.keys(parsedArgs).length !== 1)) {
        console.error('Usage: node certificate.js --action <load|extract|fetch> [--pem-path <path_to_pem_file> --domain <domain_name>] --json-path <path_to_json_file>');
        process.exit(1);
    }

    return parsedArgs;
}

function loadCertificate(pemPath, domain, jsonPath) {
    try {
        const pemContent = fs.readFileSync(pemPath, 'utf8');

        const privateKeyMatch = pemContent.match(/-----BEGIN (?:RSA )?PRIVATE KEY-----[\s\S]+?-----END (?:RSA )?PRIVATE KEY-----/);
        if (!privateKeyMatch) {
            throw new Error(`No private key found in ${pemPath} .`);
        }
        const privateKey = privateKeyMatch[0];

        const certMatches = pemContent.match(/-----BEGIN CERTIFICATE-----[\s\S]+?-----END CERTIFICATE-----/g);
        if (!certMatches || certMatches.length === 0) {
            throw new Error(`No certificate found in ${pemPath} .`);
        }
        
        // Join all certificates
        const certificate = certMatches.join('\n');

        const cert = new crypto.X509Certificate(certMatches[0]); 
        const notBefore = cert.validFrom;
        const notAfter = cert.validTo;

        const httpsCertContent = {
            domain: domain,
            key: privateKey,
            cert: certificate, 
            notBefore: new Date(notBefore).toISOString(),
            notAfter: new Date(notAfter).toISOString()
        };

        fs.writeFileSync(jsonPath, JSON.stringify(httpsCertContent, null, 2));

        console.log(`Certificate information saved to ${jsonPath} .`);
    } catch (error) {
        console.error(`Error loading certificate: ${error.message} .`);
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
        console.error(`Error extracting certificate: ${error.message} .`);
        process.exit(1);
    }
}

const args = parseCommandLineArgs();

try {
    if (args.action === 'load') {
        loadCertificate(args['pem-path'], args.domain, args['json-path']);
    } else if (args.action === 'extract') {
        extractCertificate(args['json-path']);
    } else if (args.action === 'fetch') {
        getCertificate();
    } else {
        throw new Error('Invalid action specified!');
    }
} catch (error) {
    console.error(`Error: ${error.message}`);
    process.exit(1);
}