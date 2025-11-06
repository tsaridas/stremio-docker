#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const https = require('https');
const http = require('http');
const { URL } = require('url');

const LOCALSTORAGE_FILE = path.join(__dirname, 'localStorage.json');


async function fetchManifest(url) {
    return new Promise((resolve, reject) => {
        const parsedUrl = new URL(url);
        const client = parsedUrl.protocol === 'https:' ? https : http;
        
        const options = {
            hostname: parsedUrl.hostname,
            port: parsedUrl.port || (parsedUrl.protocol === 'https:' ? 443 : 80),
            path: parsedUrl.pathname + parsedUrl.search,
            method: 'GET',
            headers: {
                'User-Agent': 'Stremio-Docker-Addon-Loader/1.0'
            }
        };

        const req = client.request(options, (res) => {
            if (res.statusCode !== 200) {
                reject(new Error(`Failed to fetch manifest: ${res.statusCode} ${res.statusMessage}`));
                return;
            }

            let data = '';
            res.on('data', (chunk) => {
                data += chunk;
            });

            res.on('end', () => {
                try {
                    const manifest = JSON.parse(data);
                    resolve(manifest);
                } catch (e) {
                    reject(new Error(`Invalid JSON in manifest: ${e.message}`));
                }
            });
        });

        req.on('error', (err) => {
            reject(err);
        });

        req.setTimeout(10000, () => {
            req.destroy();
            reject(new Error('Request timeout'));
        });

        req.end();
    });
}

function normalizeUrl(url) {
    try {
        const parsed = new URL(url);
        parsed.pathname = parsed.pathname.replace(/\/+$/, '') || '/';
        return parsed.toString();
    } catch (e) {
        return url;
    }
}

function addonExists(localStorageData, transportUrl) {
    if (!localStorageData.profile || !localStorageData.profile.addons) {
        return false;
    }

    const normalizedUrl = normalizeUrl(transportUrl);
    
    return localStorageData.profile.addons.some(addon => {
        if (addon.transportUrl) {
            return normalizeUrl(addon.transportUrl) === normalizedUrl;
        }
        return false;
    });
}

function addonExistsById(localStorageData, manifestId) {
    if (!localStorageData.profile || !localStorageData.profile.addons) {
        return false;
    }

    return localStorageData.profile.addons.some(addon => {
        return addon.manifest && addon.manifest.id === manifestId;
    });
}

function createAddonFromManifest(manifest, transportUrl) {
    return {
        manifest: manifest,
        transportUrl: transportUrl,
        flags: {
            official: false,
            protected: false
        }
    };
}

function normalizeStremioProtocol(url) {
    if (url && url.startsWith('stremio://')) {
        return url.replace(/^stremio:\/\//, 'https://');
    }
    return url;
}

function parseUrlsFromString(str) {
    if (!str) return [];
    
    const protocolPattern = /(https?:\/\/|stremio:\/\/)/gi;
    const matches = [...str.matchAll(protocolPattern)];
    const urlCount = matches.length;
    
    let urls = [];
    
    if (urlCount > 1) {
        const parts = [];
        for (let i = 0; i < matches.length; i++) {
            const start = matches[i].index;
            const end = i < matches.length - 1 ? matches[i + 1].index : str.length;
            let url = str.substring(start, end).trim();
            url = url.replace(/^[,|\s]+|[,\s]+$/g, '');
            if (url) {
                parts.push(url);
            }
        }
        urls = parts;
    } else if (urlCount === 1) {
        urls = [str.trim()];
    } else {
        if (str.includes('\n')) {
            urls = str.split(/\r?\n/).map(s => s.trim());
        } else if (str.includes(' ')) {
            urls = str.split(/\s+/).map(s => s.trim());
        } else {
            urls = [str.trim()];
        }
    }
    
    return urls
        .filter(line => line && !line.startsWith('#'))
        .map(url => normalizeStremioProtocol(url));
}

function loadUrls() {
    const addonsEnv = process.env.ADDONS;
    if (addonsEnv) {
        const urls = parseUrlsFromString(addonsEnv)
            .filter(line => {
                try {
                    new URL(line);
                    return true;
                } catch {
                    console.warn(`Skipping invalid URL: ${line}`);
                    return false;
                }
            });
        
        if (urls.length > 0) {
            console.log(`Loaded ${urls.length} URL(s) from ADDONS environment variable`);
        } else {
            console.log(`ADDONS environment variable is set but contains no valid URLs`);
        }
        return urls;
    }

    const urls = process.argv.slice(2)
        .map(url => normalizeStremioProtocol(url))
        .filter(url => {
            try {
                new URL(url);
                return true;
            } catch {
                console.warn(`Skipping invalid URL: ${url}`);
                return false;
            }
        });

    if (urls.length === 0) {
        console.log(`Usage: node add-addons.js [URL1] [URL2] ...`);
        console.log(`   OR: Set ADDONS environment variable (comma, space, or newline separated)`);
        console.log(`   URLs should point to Stremio addon manifest.json files`);
        process.exit(1);
    }

    return urls;
}

function ensureManifestUrl(url) {
    try {
        const parsed = new URL(url);
        if (!parsed.pathname.endsWith('/manifest.json')) {
            parsed.pathname = parsed.pathname.replace(/\/+$/, '');
            if (!parsed.pathname.endsWith('manifest.json')) {
                parsed.pathname += (parsed.pathname.endsWith('/') ? '' : '/') + 'manifest.json';
            }
        }
        return parsed.toString();
    } catch {
        return url;
    }
}

async function main() {
    try {
        if (!fs.existsSync(LOCALSTORAGE_FILE)) {
            console.error(`Error: ${LOCALSTORAGE_FILE} not found`);
            process.exit(1);
        }

        const localStorageData = JSON.parse(fs.readFileSync(LOCALSTORAGE_FILE, 'utf8'));

        if (!localStorageData.profile) {
            localStorageData.profile = {};
        }
        if (!localStorageData.profile.addons) {
            localStorageData.profile.addons = [];
        }

        const urls = loadUrls();
        
        if (urls.length === 0) {
            console.log(`No addon URLs to process. Exiting.`);
            return;
        }
        
        console.log(`Processing ${urls.length} addon URL(s)...\n`);

        const urlsToProcess = [];
        const skippedUrls = [];
        
        for (const url of urls) {
            const manifestUrl = ensureManifestUrl(url);
            
            if (addonExists(localStorageData, manifestUrl)) {
                console.log(`⏭️  Skipping ${manifestUrl}: Addon already exists (by URL)`);
                skippedUrls.push({ url: manifestUrl, reason: 'exists_by_url' });
                continue;
            }
            
            urlsToProcess.push(manifestUrl);
        }

        if (urlsToProcess.length === 0) {
            console.log(`\n⚠️  All addons already exist. No new addons to add.`);
            return;
        }

        console.log(`Fetching ${urlsToProcess.length} manifest(s) concurrently...\n`);

        const fetchPromises = urlsToProcess.map(async (manifestUrl) => {
            try {
                console.log(`Fetching: ${manifestUrl}`);
                const manifest = await fetchManifest(manifestUrl);
                return { success: true, manifestUrl, manifest };
            } catch (error) {
                console.error(`❌ Error fetching ${manifestUrl}: ${error.message}`);
                return { success: false, manifestUrl, error: error.message };
            }
        });

        const results = await Promise.all(fetchPromises);

        let added = 0;
        let skipped = skippedUrls.length;
        let errors = 0;

        for (const result of results) {
            if (!result.success) {
                errors++;
                continue;
            }

            const { manifestUrl, manifest } = result;

            if (!manifest.id) {
                console.error(`  ❌ Error: Manifest missing 'id' field for ${manifestUrl}\n`);
                errors++;
                continue;
            }

            if (addonExistsById(localStorageData, manifest.id)) {
                console.log(`  ⏭️  Skipping ${manifestUrl}: Addon already exists (by ID: ${manifest.id})\n`);
                skipped++;
                continue;
            }

            const addon = createAddonFromManifest(manifest, manifestUrl);

            localStorageData.profile.addons.push(addon);
            console.log(`  ✅ Added: ${manifest.name || manifest.id} (${manifest.id})\n`);
            added++;
        }

        if (added > 0) {
            fs.writeFileSync(LOCALSTORAGE_FILE, JSON.stringify(localStorageData, null, 2), 'utf8');
            console.log(`\n✅ Successfully updated ${LOCALSTORAGE_FILE}`);
            console.log(`   Added: ${added} addon(s)`);
            if (skipped > 0) {
                console.log(`   Skipped: ${skipped} addon(s) (already exists)`);
            }
            if (errors > 0) {
                console.log(`   Errors: ${errors} addon(s)`);
            }
        } else {
            console.log(`\n⚠️  No new addons were added.`);
            if (skipped > 0) {
                console.log(`   Skipped: ${skipped} addon(s) (already exists)`);
            }
            if (errors > 0) {
                console.log(`   Errors: ${errors} addon(s)`);
            }
        }

    } catch (error) {
        console.error(`\n❌ Fatal error: ${error.message}`);
        process.exit(1);
    }
}

main();
