import { avSession } from "@kit.AVSessionKit";

export default class MediaData {
  queueItemDescFirst: avSession.AVMediaDescription = {
    assetId: '001',
    title: 'First music',
    subtitle: 'music_sub_name',
    description: 'music_description',
    mediaImage: 'http://www.xxx.com',
    extras: {
      'extras': 'any'
    }
  };
  queueItemFirst: avSession.AVQueueItem = {
    itemId: 0,
    description: this.queueItemDescFirst
  };
  queueItemDescSecond: avSession.AVMediaDescription = {
    assetId: '002',
    title: 'Second music',
    subtitle: 'music_sub_name',
    description: 'music_description',
    mediaImage: 'http://www.xxx.com',
    extras: {
      'extras': 'any'
    }
  };
  queueItemSecond: avSession.AVQueueItem = {
    itemId: 1,
    description: this.queueItemDescSecond
  };
  queueItemDescThird: avSession.AVMediaDescription = {
    assetId: '003',
    title: 'Third music',
    subtitle: 'music_sub_name',
    description: 'music_description',
    mediaImage: 'http://www.xxx.com',
    extras: {
      'extras': 'any'
    }
  };
  queueItemThird: avSession.AVQueueItem = {
    itemId: 2,
    description: this.queueItemDescThird
  };

  //新增queueInfoList 方便切歌时用
  queueInfoList:Array<avSession.AVQueueItem> = [this.queueItemFirst, this.queueItemSecond, this.queueItemThird]

  //一二三首歌的数据
  avMetadataFirst: avSession.AVMetadata = {
    assetId: '0',
    title: this.queueItemDescFirst.title,
    artist: 'First artist',
    displayTags: avSession.DisplayTag.TAG_AUDIO_VIVID,
    duration: 219000,
    avQueueName: 'FirstPlayList',
    avQueueId: 'FirstPlayList',
    avQueueImage: 'first.png',
    // For video session.
    skipIntervals: avSession.SkipIntervals.SECONDS_30
  };
  avMetadataSecond: avSession.AVMetadata = {
    assetId: '1',
    title: this.queueItemDescSecond.title,
    artist: 'Second artist',
    duration: 219000,
    avQueueName: 'SecondPlayList',
    avQueueId: 'SecondPlayList',
    avQueueImage: 'second.png'
  };
  avMetadataThird: avSession.AVMetadata = {
    assetId: '2',
    title: this.queueItemDescThird.title,
    artist: 'Third artist',
    duration: 219000,
    avQueueName: 'ThirdPlayList',
    avQueueId: 'ThirdPlayList',
    avQueueImage: 'third.png'
  };
  //播放列表
  queueItems: Array<avSession.AVQueueItem> =
    [this.queueItemFirst, this.queueItemSecond, this.queueItemThird]
  avMetadataList: Array<avSession.AVMetadata> = [this.avMetadataFirst, this.avMetadataSecond, this.avMetadataThird];

  static loopModeList = [
    $r('app.media.ic_public_order_play'),
    $r('app.media.ic_public_single_cycle'),
    $r('app.media.ic_public_list_cycle'),
    $r('app.media.ic_public_random')
  ];
}