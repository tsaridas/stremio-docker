async function loadJsonAndStoreInLocalStorage() {
    try {
        const response = await fetch('localStorage.json');

        if (!response.ok) {
            throw new Error('Failed to load localStorage.json');
        }

        const data = await response.json();

        Object.entries(data).forEach(([key, value]) => {
            if (!localStorage.getItem(key)) {
                localStorage.setItem(key, JSON.stringify(value));
            }
        });

        console.log('Data successfully stored in localStorage from localStorage.json');
    } catch (error) {
        console.error('Error loading JSON data from localStorage.json:', error);
    }
}

loadJsonAndStoreInLocalStorage();