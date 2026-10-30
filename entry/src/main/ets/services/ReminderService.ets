// 句栖 · 回访提醒：把「已解决 / 已放下」的旧事排进系统提醒
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { common } from '@kit.AbilityKit';
import { Store } from '../data/Store';

export class ReminderService {
  private static running: boolean = false;
  private static queued: boolean = false;
  private static queuedAsk: boolean = false;

  private static dayKey(ts: number): string {
    const d = new Date(ts);
    return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
  }

  private static request(at: number, count: number): reminderAgentManager.ReminderRequestCalendar {
    const d = new Date(at);
    return {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
      dateTime: {
        year: d.getFullYear(),
        month: d.getMonth() + 1,
        day: d.getDate(),
        hour: d.getHours(),
        minute: d.getMinutes(),
        second: 0
      },
      title: '句栖 · 轻轻回访',
      content: `有${count}件旧事，到了轻轻回看的时间。`,
      expiredContent: `有${count}件旧事，等你回来轻轻看一眼。`,
      slotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
      wantAgent: {
        pkgName: 'com.juxia.app',
        abilityName: 'EntryAbility',
        parameters: { 'revisit': '1' }
      }
    };
  }

  static async rescheduleAll(ctx: common.UIAbilityContext, requestPermission: boolean = true): Promise<boolean> {
    if (ReminderService.running) {
      ReminderService.queued = true;
      if (requestPermission) ReminderService.queuedAsk = true;
      return true;
    }
    ReminderService.running = true;
    try {
      return await ReminderService.doReschedule(ctx, requestPermission);
    } finally {
      ReminderService.running = false;
      if (ReminderService.queued) {
        ReminderService.queued = false;
        const ask: boolean = ReminderService.queuedAsk;
        ReminderService.queuedAsk = false;
        setTimeout(() => {
          ReminderService.rescheduleAll(ctx, ask);
        }, 0);
      }
    }
  }

  private static async doReschedule(ctx: common.UIAbilityContext, requestPermission: boolean): Promise<boolean> {
    const st = Store.get();
    // 清掉旧的按天聚合提醒
    const oldMap: Record<string, number> = st.data.meta.revisitReminderIds;
    for (const key of Object.keys(oldMap)) {
      const id: number = oldMap[key];
      if (id > 0) {
        try {
          await reminderAgentManager.cancelReminder(id);
        } catch (err) {
        }
      }
    }
    st.data.meta.revisitReminderIds = {};
    st.saveKv();
    try {
      await reminderAgentManager.cancelAllReminders();
    } catch (e) {
    }

    if (requestPermission) {
      const allowed: boolean = await ReminderService.ensureNotify(ctx);
      if (!allowed) {
        return false;
      }
    } else {
      try {
        if (!(await notificationManager.isNotificationEnabled())) return false;
      } catch (e) {
        return false;
      }
    }

    const now: number = Date.now();
    const times: Record<string, number> = {};
    const counts: Record<string, number> = {};
    for (const e of st.data.own) {
      if (e.archAt <= 0 || e.revisitAt <= now) continue;
      const key: string = ReminderService.dayKey(e.revisitAt);
      if (times[key] === undefined || e.revisitAt < times[key]) times[key] = e.revisitAt;
      counts[key] = (counts[key] === undefined ? 0 : counts[key]) + 1;
    }
    const ids: Record<string, number> = {};
    let ok: boolean = true;
    for (const key of Object.keys(times)) {
      try {
        const id: number = await reminderAgentManager.publishReminder(
          ReminderService.request(times[key], counts[key])
        );
        ids[key] = id;
      } catch (e) {
        ok = false;
        const err = e as Error;
        console.error('juxia reminder publish fail', String(err.message ?? ''));
      }
    }
    st.data.meta.revisitReminderIds = ids;
    st.saveKv();
    return ok;
  }

  static async cancelAll(ctx: common.UIAbilityContext): Promise<void> {
    const st = Store.get();
    const map: Record<string, number> = st.data.meta.revisitReminderIds;
    for (const key of Object.keys(map)) {
      try {
        await reminderAgentManager.cancelReminder(map[key]);
      } catch (err) {
      }
    }
    st.data.meta.revisitReminderIds = {};
    st.saveKv();
  }

  private static async ensureNotify(ctx: common.UIAbilityContext): Promise<boolean> {
    try {
      if (await notificationManager.isNotificationEnabled()) {
        return true;
      }
      await notificationManager.requestEnableNotification(ctx);
      return await notificationManager.isNotificationEnabled();
    } catch (e) {
      return false;
    }
  }

  static async enableNotifications(ctx: common.UIAbilityContext): Promise<boolean> {
    return await ReminderService.ensureNotify(ctx);
  }

  static async status(ctx: common.UIAbilityContext): Promise<string> {
    try {
      const enabled: boolean = await notificationManager.isNotificationEnabled();
      const list: reminderAgentManager.ReminderRequest[] = await reminderAgentManager.getValidReminders();
      return `通知${enabled ? '已开启' : '未开启'}；系统里已有 ${list.length} 条句栖提醒`;
    } catch (e) {
      const err = e as Error;
      return '读取提醒状态失败：' + (err.message.length > 0 ? err.message : '未知原因');
    }
  }
}



