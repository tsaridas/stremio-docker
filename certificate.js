const fs = require('fs');
const process = require('process');

async function getCertificate() {
  try {
    const ipAddress = process.env.IPADDRESS;
    const response = await fetch('http://api.strem.io/api/certificateGet', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        authKey: null,
        ipAddress: ipAddress,
      }),
    });

    if (!response.ok) {
      throw new Error(`HTTP error! Status: ${response.status} ${response.statusText}`);
    }

    const data = await response.json();
    const certResp = JSON.parse(data.result.certificate);

    if (!certResp) {
      throw new Error('Missing certificate or privateKey in API response');
    }

    const combinedCertificates = Buffer.from(certResp.contents.Certificate, 'base64').toString() + Buffer.from(certResp.contents.PrivateKey, 'base64').toString();

    fs.writeFileSync('certificates.pem', combinedCertificates);

    console.log('Certificates saved successfully!');
  } catch (error) {
    console.error('Error fetching certificate:', error);
  }
}

getCertificate();