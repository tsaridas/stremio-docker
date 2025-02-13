async function loadJsonAndStoreInLocalStorage() {
    try {
        const response = await fetch('localStorage.json');

        if (!response.ok) {
            throw new Error('Failed to load localStorage.json');
        }

        const data = await response.json();

        function processLocalStorageData(data) {
            let reload = false;
            Object.entries(data).forEach(([key, value]) => {
                if (!localStorage.getItem(key)) {
                    localStorage.setItem(key, JSON.stringify(value));
                } else if (key === 'streaming_server_urls') {
                    const existingData = JSON.parse(localStorage.getItem(key) || '{"uid": null, "items": {}}');
                    const newData = value;

                    if (existingData.items != newData.items) {
                        const mergedItems = {
                            ...existingData.items,
                            ...newData.items
                        };
    
                        const mergedData = {
                            uid: existingData.uid,
                            items: mergedItems
                        };
                        localStorage.setItem(key, JSON.stringify(mergedData));
                        reload = true;
                    }

                } else if (key === 'profile') {
                    const existingProfile = JSON.parse(localStorage.getItem(key) || '{}');
                    if (existingProfile.settings.streamingServerUrl !=  value.settings.streamingServerUrl) {
                        existingProfile.settings.streamingServerUrl = value.settings.streamingServerUrl;
                        localStorage.setItem(key, JSON.stringify(existingProfile, null, 2));
                        reload = true;
                    }
                }
            });
            if (reload) {
                location.reload();
            }
        }

        processLocalStorageData(data); // Process the data immediately

        setInterval(() => {
            processLocalStorageData(data); // Reuse the data to set interval
        }, 5000);
        

        console.log('Data successfully stored in localStorage from localStorage.json');
    } catch (error) {
        console.error('Error loading JSON data from localStorage.json:', error);
    }
}

loadJsonAndStoreInLocalStorage();