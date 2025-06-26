import { test as baseTest } from '@playwright/test';

type MyFixtures = {
  serverURL: string;
  webURL: string;
  auth: boolean;
};

export const test = baseTest.extend<MyFixtures>({
  serverURL: async ({}, use) => {
    const serverURL = process.env.SERVER_URL || 'http://172.18.0.3:8080';
    await use(serverURL);
  },
  webURL: async ({}, use) => {
    const webURL = process.env.WEB_URL || 'http://172.18.0.3:8080';
    await use(webURL);
  },
  auth: async ({}, use) => {
    const auth = process.env.AUTH === 'true' || false;
    await use(auth);
  },
});
