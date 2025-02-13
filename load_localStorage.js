let isRunning = false; 
let cachedData = null;

async function loadJsonAndStoreInLocalStorage() {
    if (isRunning) return;
    
    try {
        isRunning = true;

        if (!cachedData) {
            const response = await fetch('localStorage.json');
            if (!response.ok) {
                throw new Error('Failed to load localStorage.json');
            }
            cachedData = await response.json();
        }

        await processLocalStorageData(cachedData);
        
        await new Promise(resolve => setTimeout(resolve, 2000));

    } catch (error) {
        console.error('Error loading JSON data from localStorage.json:', error);
    } finally {
        isRunning = false;
    }
}

function processLocalStorageData(data) {
    let reload = false;
    Object.entries(data).forEach(([key, value]) => {
        if (!localStorage.getItem(key)) {
            localStorage.setItem(key, JSON.stringify(value));
        } else if (key === 'streaming_server_urls') {
            const existingData = JSON.parse(localStorage.getItem(key));
            const newData = value;

            if (Object.keys(newData.items).some(key => !Object.keys(existingData.items).includes(key))) {
                const mergedItems = {
                    ...existingData.items,
                    ...newData.items
                };

                const mergedData = {
                    uid: existingData.uid,
                    items: mergedItems
                };
                localStorage.setItem(key, JSON.stringify(mergedData));
                console.log("Setting new values for streaming server", JSON.stringify(mergedData));
                reload = true;
            }
        } else if (key === 'profile') {
            const existingProfile = JSON.parse(localStorage.getItem(key) || '{}');
            if (existingProfile.settings?.streamingServerUrl !== value.settings?.streamingServerUrl) {
                existingProfile.settings.streamingServerUrl = value.settings.streamingServerUrl;
                console.log("Setting new values for profile", existingProfile);
                localStorage.setItem(key, JSON.stringify(existingProfile, null, 2));
                reload = true;
            }
        }
    });
    
    if (reload) {
        console.log("Changes detected, reloading page in 5 seconds...");
        location.reload();
    }
}

loadJsonAndStoreInLocalStorage();

setInterval(loadJsonAndStoreInLocalStorage, 5000);