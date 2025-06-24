let isRunning = false; 
let cachedData = {};
let items = {};
let server_url = null;

async function loadJsonAndStoreInLocalStorage() {
    if (isRunning) return;
    
    try {
        isRunning = true;


        const response = await fetch('localStorage.json');
        if (!response.ok) {
            throw new Error(`Failed to load localStorage.json: ${response.status} ${response.statusText}`);
        }
        cachedData = await response.json();
        console.log("Received cachedData", cachedData)

        const serverUrlExists = await fetch('server_url.env', { method: 'HEAD' });
        if (!serverUrlExists.ok) {
            const timestamp = new Date().toISOString();
            server_url = getCurrentUrl().toString();
            items[server_url] = timestamp;
            console.log('Server URL does not exist. Setting Server URL automagically.', server_url, items);
        } else {
            items = cachedData.streaming_server_urls.items;
            server_url = Object.keys(items)[0];
            console.log('Server URL exists.', items, server_url);
        }

        processLocalStorageData();

    } catch (error) {
        console.error('Error loading JSON data from localStorage.json:', error);
    } finally {
        isRunning = false;
    }
}

function processLocalStorageData() {
    let reload = false;
    console.log("Items and server_url are :", items, server_url)
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

            if (existingProfile.settings?.streamingServerUrl !== server_url) {
                existingProfile.settings.streamingServerUrl = server_url;
                localStorage.setItem(key, JSON.stringify(existingProfile));
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
        console.log("We received cached data", cachedData)
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
