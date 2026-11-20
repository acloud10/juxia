import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { commentManager } from '@kit.AppGalleryKit';

export class ReviewService {
  static open(context: common.UIAbilityContext, toast: (msg: string) => void): void {
    commentManager.showCommentDialog(context).then(() => {
    }).catch((error: BusinessError) => {
      const code: number = error.code;
      if (code === 1021500007 || code === 1021500008 || code === 1021500009) {
        toast('已评价过，正在打开应用市场。');
        ReviewService.openMarket(context, toast);
        return;
      }
      if (code === 1021500003 || code === 1021500005 || code === 1021500006) {
        ReviewService.openMarket(context, toast);
        return;
      }
      toast('现在无法打开评价，请稍后再试。');
    });
  }

  private static openMarket(context: common.UIAbilityContext, toast: (msg: string) => void): void {
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: 'store://appgallery.huawei.com/app/detail?id=com.juxia.app&action=write-review'
    };
    context.startAbility(want).catch(() => {
      toast('请到华为应用市场搜索「句栖」，在详情页写评价。');
    });
  }
}
