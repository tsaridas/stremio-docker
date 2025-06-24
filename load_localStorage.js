let isRunning = false; 
let cachedData = null;

async function loadJsonAndStoreInLocalStorage() {
    if (isRunning) return;
    
    try {
        isRunning = true;
        let items = {};
        let server_url = "";

        const response = await fetch('localStorage.json');
        if (!response.ok) {
            throw new Error(`Failed to load localStorage.json: ${response.status} ${response.statusText}`);
        }
        cachedData = await response.json();

        const serverUrlExists = await fetch('server_url.env', { method: 'HEAD' });
        if (!serverUrlExists.ok) {
            const timestamp = new Date().toISOString();
            server_url = JSON.stringify(getCurrentUrl().toString());
            items[server_url] = timestamp;
            console.log('Server URL does not exist. Setting Server URL automagically.');
        } else {
            items = cachedData.streaming_server_urls.items;
            server_url = JSON.stringify(Object.keys(items)[0]);
            console.log('Server URL exists.');
        }

        processLocalStorageData(items, server_url);

    } catch (error) {
        console.error('Error loading JSON data from localStorage.json:', error);
    } finally {
        isRunning = false;
    }
}

function processLocalStorageData(items, server_url) {
    let reload = false;
    Object.entries(cachedData).forEach(([key, value]) => {
        if (!localStorage.getItem(key)) {
            localStorage.setItem(key, JSON.stringify(value));
        } else if (key === 'streaming_server_urls') {
            const existingData = JSON.parse(localStorage.getItem(key));
            console.log("Existing data is : ", existingData)
            if (existingData.items && !existingData.items[server_url]) {
                console.log("Server url in streaming_server_urls doesn't exist", existingData.items)
                existingData.items = items;
                localStorage.setItem(key, JSON.stringify(existingData));
                reload = true;
            }
        } else if (key === 'profile') {
            const existingProfile = JSON.parse(localStorage.getItem(key));
            if (!existingProfile.settings) {
                existingProfile.settings = {};
            }
            if (!existingProfile.settings.streamingServerUrl) {
                existingProfile.settings.streamingServerUrl = server_url;
                localStorage.setItem(key, JSON.stringify(existingProfile, null, 2));
                reload = true;
            }
        }
    });
    
    if (reload) {
        console.log("Changes detected for streamingServerUrl, reloading page ...");
        location.reload();
    }
}

async function initialize() {
    await loadJsonAndStoreInLocalStorage();
    if (cachedData) {
        setInterval(processLocalStorageData, 5000);
    }
}

// Function to get the current URL the user is browsing
function getCurrentUrl() {
    const url = window.location.href;
    const protocolIndex = url.indexOf('://') + 3;
    const index = url.indexOf('/', protocolIndex);
    const baseUrl = index === -1 ? url : url.substring(0, index);
    return baseUrl + '/';
}

// Log the current URL to the console
console.log("Current URL:", getCurrentUrl());

initialize();
