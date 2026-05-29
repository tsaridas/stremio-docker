const fs = require('fs');
const process = require('process');
const path = require('path');
const crypto = require('crypto');

function isValidIPv4(ipAddress) {
    return /^(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}$/.test(ipAddress);
}

async function fetchWithTimeout(url, options = {}, timeoutMs = 3000) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);
    try {
        return await fetch(url, { ...options, signal: controller.signal });
    } finally {
        clearTimeout(timeout);
    }
}

async function getPublicIPv4() {
    const providers = [
        {
            url: 'https://ifconfig.me/ip',
            parse: async (response) => (await response.text()).trim(),
        },
        {
            url: 'https://4.ident.me',
            parse: async (response) => (await response.text()).trim(),
        },
        {
            url: 'https://4.tnedi.me',
            parse: async (response) => (await response.text()).trim(),
        },
    ];

    const errors = [];
    for (const provider of providers) {
        try {
            const response = await fetchWithTimeout(provider.url, {}, 3000);
            if (!response.ok) {
                errors.push(`${provider.url} returned HTTP ${response.status}`);
                continue;
            }

            const ipAddress = await provider.parse(response);
            if (isValidIPv4(ipAddress)) {
                return ipAddress;
            }

            errors.push(`${provider.url} returned invalid IPv4: "${ipAddress}"`);
        } catch (error) {
            errors.push(`${provider.url} failed: ${error.message}`);
        }
    }

    throw new Error(`Unable to detect public IPv4 address from all providers: ${errors.join(' | ')}`);
}
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
        ipAddress = await getPublicIPv4();
        fs.writeFileSync('detected-ip.txt', ipAddress);
    }

    if (!isValidIPv4(ipAddress)) {
        throw new Error('Invalid IPv4 address format.');
    }

    let data;
    let attempts = 0;
    const maxAttempts = Number(process.env.MAXATTEMPTS) || 5;
    while (attempts < maxAttempts) {
        try {
            const response = await fetch('https://api.strem.io/api/certificateGet', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    authKey: null,
                    ipAddress: ipAddress,
                }),
            });

            data = await response.json();
            if (!response || !response.ok || data.error) {
                const apiMessage = data?.error?.message || `HTTP ${response?.status}`;
                throw new Error(`Failed to fetch certificate: ${apiMessage}`);
            }
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