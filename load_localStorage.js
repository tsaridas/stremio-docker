let isRunning = false; 
let cachedData = null;

async function loadJsonAndStoreInLocalStorage() {
    if (isRunning) return;
    
    try {
        isRunning = true;

        const response = await fetch('localStorage.json');
        if (!response.ok) {
            throw new Error(`Failed to load localStorage.json: ${response.status} ${response.statusText}`);
        }
        cachedData = await response.json();

        processLocalStorageData(cachedData);

    } catch (error) {
        console.error('Error loading JSON data from localStorage.json:', error);
    } finally {
        isRunning = false;
    }
}

function processLocalStorageData() {
    let reload = false;
    Object.entries(cachedData).forEach(([key, value]) => {
        if (!localStorage.getItem(key)) {
            localStorage.setItem(key, JSON.stringify(value));
        } else if (key === 'streaming_server_urls') {
            const existingData = JSON.parse(localStorage.getItem(key));
            const urlTimestamp = { [getCurrentUrl().toString()]: [new Date().toISOString()] };
            const mergedItems = {...value.items, ...urlTimestamp };
            const mergedData = {
                uid: existingData.uid,
                items: mergedItems
            };

            if (Object.keys(mergedData.items).some(key => !Object.keys(existingData.items).includes(key))) {
                const mergedItems = {
                    ...existingData.items,
                    ...value.items
                };

                const mergedData = {
                    uid: existingData.uid,
                    items: mergedItems
                };
                localStorage.setItem(key, JSON.stringify(mergedData));
                reload = true;
            }
        } else if (key === 'profile') {
            const existingProfile = JSON.parse(localStorage.getItem(key));
            if (existingProfile.settings?.streamingServerUrl !== value.settings?.streamingServerUrl) {
                existingProfile.settings.streamingServerUrl = { [getCurrentUrl().toString()]: [new Date().toISOString()] };
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
