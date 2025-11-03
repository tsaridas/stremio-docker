let isRunning = false; 
let cachedData = {};
let items = {};
let server_url = null;
let setServerUrlEnabled = false;
let setAddonsFileExists = false;

async function checkServerUrlFiles() {
    
    try {
        const autoServerUrlResponse = await fetch('autoserver_url.env', { method: 'HEAD' });
        if (autoServerUrlResponse.ok) {
            setServerUrlEnabled = true;
            const timestamp = new Date().toISOString();
            server_url = getCurrentUrl().toString();
            items[server_url] = timestamp;
            console.log('Auto Server URL enabled. Setting Server URL from current URL.', server_url, items);
            return;
        }
    } catch (error) {
    }
    
    try {
        const serverUrlResponse = await fetch('server_url.env', { method: 'HEAD' });
        if (serverUrlResponse.ok) {
            setServerUrlEnabled = true;
            if (cachedData.streaming_server_urls && cachedData.streaming_server_urls.items) {
                items = cachedData.streaming_server_urls.items;
                server_url = Object.keys(items)[0];
                console.log('Server URL file exists. Setting up with localStorage file.', items, server_url);
            }
        }
    } catch (error) {
    }
}

async function checkAddonsFile() {
    try {
        const setAddonsResponse = await fetch('set_addons.env', { method: 'HEAD' });
        if (setAddonsResponse.ok) {
            setAddonsFileExists = true;
        }
    } catch (error) {
    }
}

async function loadJsonAndStoreInLocalStorage() {
    if (isRunning) return;
    
    try {
        isRunning = true;

        const response = await fetch('localStorage.json');
        if (!response.ok) {
            cachedData = {};
            return;
        }
        cachedData = await response.json();

        await checkServerUrlFiles();
        await checkAddonsFile();

        processLocalStorageData();

    } catch (error) {
        console.info('localStorage.json not available. Using browser localStorage only.');
    } finally {
        isRunning = false;
    }
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

function addonExistsInArray(addons, addon) {
    if (!addons || !Array.isArray(addons)) return false;
    
    const normalizedUrl = addon.transportUrl ? normalizeUrl(addon.transportUrl) : null;
    const manifestId = addon.manifest?.id;
    
    return addons.some(existing => {
        if (normalizedUrl && existing.transportUrl) {
            if (normalizeUrl(existing.transportUrl) === normalizedUrl) {
                return true;
            }
        }
        if (manifestId && existing.manifest?.id === manifestId) {
            return true;
        }
        return false;
    });
}

function processLocalStorageData() {
    let reload = false;
    Object.entries(cachedData).forEach(([key, value]) => {
        if (!localStorage.getItem(key)) {
            localStorage.setItem(key, JSON.stringify(value));
        } else if (setServerUrlEnabled && key === 'streaming_server_urls') {
            const existingData = JSON.parse(localStorage.getItem(key));
            if (existingData.items && !existingData.items[server_url]) {
                existingData.items = items;
                localStorage.setItem(key, JSON.stringify(existingData));
                reload = true;
            }
        } else if (key === 'profile') {
            const existingProfile = JSON.parse(localStorage.getItem(key));
            let profileChanged = false;

            if (setServerUrlEnabled && server_url && existingProfile.settings?.streamingServerUrl !== server_url) {
                existingProfile.settings.streamingServerUrl = server_url;
                profileChanged = true;
            }

            if (setAddonsFileExists && value.addons && Array.isArray(value.addons)) {
                const existingAddons = Array.isArray(existingProfile.addons) ? existingProfile.addons : [];
                let addonsUpdated = false;

                value.addons.forEach(newAddon => {
                    if (!addonExistsInArray(existingAddons, newAddon)) {
                        existingAddons.push(newAddon);
                        console.log('Adding addon:', newAddon);
                        addonsUpdated = true;
                    }
                });

                if (addonsUpdated) {
                    existingProfile.addons = existingAddons;
                    profileChanged = true;
                }
            }

            if (profileChanged) {
                console.log('Profile changed, saving to localStorage and reloading page ...', existingProfile);
                localStorage.setItem(key, JSON.stringify(existingProfile));
                reload = true;
            }
        }
    });
    
    if (reload) {
        console.log("Changes detected, reloading page ...");
        location.reload();
    }
}

async function initialize() {
    await loadJsonAndStoreInLocalStorage();
    if (Object.keys(cachedData).length !== 0) {
        setInterval(processLocalStorageData, 5000);
    }
}

function getCurrentUrl() {
    const url = window.location.href;
    const protocolIndex = url.indexOf('://') + 3;
    const index = url.indexOf('/', protocolIndex);
    const baseUrl = index === -1 ? url : url.substring(0, index);
    return baseUrl + '/';
}

initialize();
