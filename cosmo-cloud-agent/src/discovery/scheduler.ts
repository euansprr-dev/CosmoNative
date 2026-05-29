import cron from 'node-cron';
import { config } from '../config';
import { refreshDueDiscoverySources } from './jobs';

const tasks: cron.ScheduledTask[] = [];

export function startDiscoveryScheduler(): void {
  if (tasks.length > 0) return;

  const timezone = config.timezone;

  tasks.push(
    cron.schedule('17 */2 * * *', async () => {
      console.log('🔎 Discovery hot-lane refresh starting');
      const result = await refreshDueDiscoverySources(10);
      console.log(`🔎 Discovery hot-lane complete: ${result.sources} sources, ${result.posts} posts`);
    }, { timezone }),
    cron.schedule('9 3 * * *', async () => {
      console.log('🔎 Discovery daily refresh starting');
      const result = await refreshDueDiscoverySources(100);
      console.log(`🔎 Discovery daily complete: ${result.sources} sources, ${result.posts} posts`);
    }, { timezone }),
    cron.schedule('41 4 * * 1', async () => {
      console.log('🔎 Discovery weekly exploration starting');
      const result = await refreshDueDiscoverySources(250);
      console.log(`🔎 Discovery weekly exploration complete: ${result.sources} sources, ${result.posts} posts`);
    }, { timezone })
  );

  console.log(`🔎 Discovery scheduler started (timezone: ${timezone})`);
}

export function stopDiscoveryScheduler(): void {
  for (const task of tasks) task.stop();
  tasks.length = 0;
}
