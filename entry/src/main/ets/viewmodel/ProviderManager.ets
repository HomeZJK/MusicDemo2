import MediaData from "../model/MediaData"
import { media } from "@kit.MediaKit"
import MediaPlayer, { AVPlayerState } from "../utils/MediaPlayerUtils"
import { avSession } from "@kit.AVSessionKit"
import { wantAgent } from "@kit.AbilityKit"
import backgroundTaskManager from "@ohos.resourceschedule.backgroundTaskManager"

/**
 * AVMetadata 就是向系统和用户展示“现在正在播放什么”的详细信息集，是 AVSession 与系统 UI（锁屏、通知栏等）进行信息交互的核心数据载体。
 */
export class ProviderFeature {
  private static providerSelf: ProviderFeature | undefined
  private mediaData: MediaData = new MediaData()
  private avPlayer: media.AVPlayer | undefined
  private session?:avSession.AVSession
  private currentState:avSession.AVPlaybackState = {
    state:avSession.PlaybackState.PLAYBACK_STATE_PAUSE
  }
  private currentTime:number = 0
  //为什么不用avSession
  // private currentPlayItem:avSession.AVQueueItem | undefined

  //为啥要这么写，写一大串看又看不懂
  private currentPlayItem: SubscribedAbstractProperty<avSession.AVQueueItem> =
    AppStorage.setAndLink('currentPlayItem', {} as avSession.AVQueueItem)
  //好像懂一点点了，可能跟状态变量有点关系
  private isPlaying: SubscribedAbstractProperty<boolean> = AppStorage.setAndLink('isPlaying', false)

  //收藏点赞功能需要的字段

  //创建一个Map来存储<assetId, isFavorite>的映射，并链接到AppStorage
  private isFavorMap:SubscribedAbstractProperty<Map<string, boolean>> = AppStorage.setAndLink<Map<string, boolean>>('isFavorMap', new Map<string , boolean>())

  //单例模式
  static async getInstance(): Promise<ProviderFeature> {
    if (!ProviderFeature.providerSelf) {
      ProviderFeature.providerSelf = new ProviderFeature()
    }
    return ProviderFeature.providerSelf
  }

  //初始化资源
  async init(): Promise<void> {
    this.avPlayer = await MediaPlayer.instance.initial()
    await MediaPlayer.instance.loadFromRawFile('test_44100_2.wav')
    //因为上面写了那么一大串，所以现在不这么写，要跟上面产生关系
    // this.currentPlayItem = this.mediaData.queueInfoList[0]
    this.currentPlayItem.set(this.mediaData.queueInfoList[0])
    // --- 新增：初始化收藏状态 ---
    // 可以在这里预设一些初始收藏状态，或者从持久化存储加载
    // 示例：假设你想让第一首歌默认被收藏
    const initialFavorMap = new Map(this.isFavorMap.get()) //获取当前Map
    const firstItemAssetId = this.mediaData.queueInfoList[0].description?.assetId
    if (firstItemAssetId) { //检查assetId 是否存在
      initialFavorMap.set(firstItemAssetId, true) //设置第一首歌为已收藏
      this.isFavorMap.set(initialFavorMap)  //更新 AppStorage
      //同步到AVPlaybackState ————实现播控中心同步的关键一步————
      this.currentState.isFavorite = true
      await this.session?.setAVPlaybackState(this.currentState)
    }else {
      console.warn('第一首歌没有assetId，不能初始化收藏按钮')
    }

    //同步播放后台和元数据
    /*
        这几行代码共同完成了AVSession的首次状态同步
        * 创建了会话（CreateAVSession）
        * 同步了内部ui状态（isPlaying.set(false)）
        * 同步了系统播放状态（setAVPlaybackState）
        * 同步了系统元数据（setAVMetadataController）
        * 这确保了应用启动时，无论是你的应用 UI 还是系统的锁屏/通知栏 UI，都对当前的播放情况（有一首歌待播放，但尚未开始）有一致的认识。这是实现无缝媒体体验的基础。
     */
    await this.CreateAVSession()  //创建并激活AVSession实例
    this.isPlaying.set(false) //设置应用内部全局播放状态为暂停
    this.currentState.state = avSession.PlaybackState.PLAYBACK_STATE_PAUSE  //设置this.currentState中的播放对象为暂停
    await this.session?.setAVPlaybackState(this.currentState)   //将this.currentState中的对象推送给AVSession。最关键的一步
    await this.setAVMetadataController(0)   //设置AVSession的元数据（AVMetadata），包括当前播放的歌曲名称，艺术家，封面图片，时常，收藏状态等。非常重要的一步
  }

  async unInit():Promise<void>{
    this.UnRegisterListener()
    if (this.avPlayer) {
      this.avPlayer.release()
    }
  }

  async UnRegisterListener():Promise<void>{
    if (this.session) {
      this.session.off('play')
      this.session.off('pause')
      this.session.off('stop')
      this.session.off('playNext')
      this.session.off('playPrevious')
    }
    //销毁已创建的会话
    this.session?.destroy((err) => {
    })
  }

  //播放与暂停控制方法
  async localPlayOrPause(): Promise<void> {
    if (!this.avPlayer) {
      return
    }
    if (this.avPlayer.state === AVPlayerState.PLAYING) {
      await this.avPlayer.pause()
      this.isPlaying.set(false)
    } else if (this.avPlayer.state === AVPlayerState.STOPPED) {
      await this.avPlayer.prepare()
      await this.avPlayer.play()
      this.isPlaying.set(true)
    } else {
      await this.avPlayer.play()
      this.isPlaying.set(true)
    }
  }

  //上一首
  async previous(): Promise<void> {
    // let previousId:number = this.currentPlayItem?.itemId as number - 1

    //好好的itemId，为什么变成了get().itemId
    let previousId: number = this.currentPlayItem?.get().itemId as number - 1
    previousId = previousId < 0 ? this.mediaData.queueInfoList.length - 1 : previousId

    // this.currentPlayItem = this.mediaData.queueItemDescFirst[previousId]
    //这里为什么又用set()了
    this.currentPlayItem.set(this.mediaData.queueInfoList[previousId])

    //正常情况下，我肯应用根据currentPlayItem中记录的资源文件重新设置是播放歌曲，但是我们只有一个资源文件，就循环播放
    await MediaPlayer.instance.loadFromRawFile('test_44100_2.wav')
    MediaPlayer.instance.onCallback('prepared', () => {
      this.localPlayOrPause()
    })

  }

  //下一首
  async next(): Promise<void> {
    // let  nextId:number = this.currentPlayItem?.itemId as number + 1
    let nextId: number = this.currentPlayItem.get().itemId as number + 1

    nextId = this.mediaData.queueInfoList.length > nextId ? nextId : 0
    // this.currentPlayItem = this.mediaData.queueInfoList[nextId]
    this.currentPlayItem.set(this.mediaData.queueInfoList[nextId])

    //复制粘贴了上面的代码
    await MediaPlayer.instance.loadFromRawFile('test_44100_2.wav')
    MediaPlayer.instance.onCallback('prepared', () => {
      this.localPlayOrPause()
    })
  }

  //播放模式
  loopMode() {

  }

  //收藏功能
  async toggleFavorite():Promise<void> {
    //获取当前播放歌曲的id
    const currentAssetId = this.currentPlayItem.get().description?.assetId
    //如果没有这个id 报错
    if (!currentAssetId) {
      console.warn('Cannot toggle favorite : Current item has no assetId')
      return
    }
    //1.获取当前收藏状态,如果该歌曲从未被收藏，则默认为false
    //这有效地处理了“查询一个不存在于 Map 中的键”时返回 undefined 的情况，确保 currentIsFavorite 总是一个布尔值。
    const currentIsFavorite = this.isFavorMap.get().get(currentAssetId) || false
    //2.计算新状态   这行代码是实现“切换收藏状态”逻辑的核心。它简单地将当前状态变成相反的状态
    const newIsFavorite = !currentIsFavorite
    //3.更新APPStorage中的收藏状态Map
    const updatedFavorMap = new Map(this.isFavorMap.get()) //创建Map的副本
    updatedFavorMap.set(currentAssetId, newIsFavorite)  //设置新状态
    this.isFavorMap.set(updatedFavorMap)  //更新AppStorage

    //————更新AVSession的PlaybackState———— 后台状态同步
    //从AppStorage获取最新的收藏状态
    // const latestIsFavorite = this.isFavorMap.get().get(currentAssetId) || false
    //更新currentState对象中的isFavorite属性
    // this.currentState.isFavorite = latestIsFavorite

    //同步到AVPlaybackState
    this.currentState.isFavorite = newIsFavorite
    await this.session?.setAVPlaybackState(this.currentState)    //将包含新收藏状态的currentState推送给AVSession，这是让系统UI（锁屏，通知栏）同步收藏状态的关键步骤
    //————结束————

    //4.更新AVSession Metadata，使锁屏，通知栏等系统ui反映新的收藏状态
    // if (this.session) {
    //   try {
    //     //获取当前的metadata
    //     let currentMetadata:avSession.AVMetadata = this.mediaData.avMetadataList[this.currentPlayItem.get().itemId]
    //     //更新isFavorite属性 !!!!这里isFavorite找不到，所以不要这一段
    //     currentMetadata.isFavorite = newIsFavorite
    //     //将更新后的metadata推送至AVSession
    //     await this.session.setAVMetadata(currentMetadata)
    //     console.info(`Toggled favorite for item ${currentAssetId}. New state: ${newIsFavorite}`)
    //   }catch (error){
    //     console.error(`Faled to update metadata for item ${currentAssetId} after toggle:`, error)
    //     //如果更新失败，可以选择回滚AppStorage中的状态
    //     const rollbackFavorMap = new Map(this.isFavorMap.get())
    //     rollbackFavorMap.set(currentAssetId, currentIsFavorite) //恢复原状态
    //     this.isFavorMap.set(rollbackFavorMap)
    //   }
    // }

    console.info(`Toggled favorite for item ${currentAssetId}. New state: ${newIsFavorite}`)
  }

  //从数据源中通过itemId获取当前正在播放的AVMetadata并设置给对话
  async setAVMetadataController(itemId:number):Promise<void>{
    let avMetadata:avSession.AVMetadata = this.mediaData.avMetadataList[itemId]
    await this.session?.setAVMetadata(avMetadata)

    //————同步当前歌曲的收藏状态到AVPlaybackState————
    const currentAssetId = avMetadata.assetId //也可以从this.currentPlayItem.get()获取
    if (currentAssetId) {
      const currentIsFavorite = this.isFavorMap.get().get(currentAssetId) || false
      this.currentState.isFavorite = currentIsFavorite
      await this.session?.setAVPlaybackState(this.currentState)
    }
    //————结束————
  }

  //创建AVSession实例，该方法表示是否创建成功的boolean，如果创建成功，就可以直接在session字段中调用
  async CreateAVSession():Promise<boolean>{
    let  ret:boolean = true
    if (this.session) {
      return ret
    }
    //这里要进行'!'非空断言
    this.session = await avSession.createAVSession(MediaPlayer.instance.context!, 'AVSessionDemo','audio')
    this.RegisterSessionListener()
    //这里要加给BusinessError加泛型<number>不然会报错
    await this.session.activate().catch((err:BusinessError<number>) => {
      if (err) {
        ret = false
      }
    })
    return ret
  }

  //注册监听
  async RegisterSessionListener():Promise<void>{
    this.session?.on('play',async  () => {
      this.avPlayer?.play()
      this.isPlaying.set(true)
      this.currentState = {
        state:avSession.PlaybackState.PLAYBACK_STATE_PLAY,
        position:{
          elapsedTime:this.currentTime,
          updateTime: new Date().getTime()
        }
      }
      await this.session?.setAVPlaybackState(this.currentState)
    })
    this.session?.on('pause',async () => {
      this.avPlayer?.pause()
      this.isPlaying.set(false)
      this.currentState = {
        state:avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
        position:{
          elapsedTime:this.currentTime,
          updateTime: new Date().getTime()
        }
      }
      await this.session?.setAVPlaybackState(this.currentState)
    })
    this.session?.on('stop',async () => {
      this.avPlayer?.stop()
      this.isPlaying.set(false)
      this.currentState.state = avSession.PlaybackState.PLAYBACK_STATE_PAUSE
      await this.session?.setAVPlaybackState(this.currentState)
    })
    this.session?.on('playNext', async () => {
      let nextId:number = this.currentPlayItem.get().itemId + 1
      nextId = this.mediaData.queueInfoList.length > nextId ? nextId : 0
      this.currentPlayItem.set(this.mediaData.queueInfoList[nextId])
      await this.setAVMetadataController(nextId)
      await MediaPlayer.instance.loadFromRawFile('test_44100_2.wav')
      MediaPlayer.instance.onCallback('prepared',async () => {
        // this.localPlayOrPause()
        //这里为什么要加await，之前不加也行啊,加了也没啥不一样
        //这里加了await后，应用-后台任务-播控中心的ui同步了
        await this.localPlayOrPause()
        this.currentState = {
          state:this.isPlaying.get() ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
          position:{
            elapsedTime:this.currentTime,
            updateTime:new Date().getTime()
          }
        }
        await this.session?.setAVPlaybackState(this.currentState)
      })
    })
    this.session?.on('playPrevious',async () => {
      let previousId: number = this.currentPlayItem?.get().itemId as number - 1
      previousId = previousId < 0 ? this.mediaData.queueInfoList.length - 1 : previousId

      this.currentPlayItem.set(this.mediaData.queueInfoList[previousId])
      await this.setAVMetadataController(previousId)
      //正常情况下，我肯应用根据currentPlayItem中记录的资源文件重新设置是播放歌曲，但是我们只有一个资源文件，就循环播放
      await MediaPlayer.instance.loadFromRawFile('test_44100_2.wav')
      MediaPlayer.instance.onCallback('prepared', async () => {
        // this.localPlayOrPause()
        //这里为什么要加await，之前不加也行啊,加了也没啥不一样
        //这里加了await后，应用-后台任务-播控中心的ui同步了
        await this.localPlayOrPause()
        this.currentState = {
          state:this.isPlaying.get() ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
          position:{
            elapsedTime:this.currentTime,
            updateTime:new Date().getTime()
          }
        }
        console.log(this.isPlaying.get() + '')
        await this.session?.setAVPlaybackState(this.currentState)
      })
      })

    //————监听来自系统UI的toggleFavorite指令———— 后台收藏状态同步
    this.session?.on('toggleFavorite', (assetId:string) => {
      //当系统UI触发收藏/取消收藏时，会调用此回调，并传入歌曲的assetId
      console.info('Received toggleFavorite from system UI for assetId:', assetId)
      //1.获取当前在AppStorage中的收藏状态
      const currentIsFavoriteInStorage = this.isFavorMap.get().get(assetId) || false
      //2.计算新状态 （取反）
      const newIsFavorite = !currentIsFavoriteInStorage
      //3.更新AppStorage中的收藏状态Map
      const updatedFavorMap = new Map(this.isFavorMap.get())
      updatedFavorMap.set(assetId, newIsFavorite)
      this.isFavorMap.set(updatedFavorMap)
      //4.更新AVSession的PlaybackState，确认状态变更
      this.currentState.isFavorite = newIsFavorite
      this.session?.setAVPlaybackState(this.currentState)

      console.info(`System UI toggled favorite for item ${assetId}. New state: ${newIsFavorite}`)
      //————结束————
    })


  }

  //单独封装一个播放和暂停的方法，用于在提供方单独点击播放和暂停时可以把播放状态同步给控制方
  async play():Promise<void>{
    this.localPlayOrPause()
    this.currentState = {
      state:this.isPlaying.get() ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
      position:{
        elapsedTime:this.currentTime,
        updateTime:new Date().getTime()
      }
    }
    await this.session?.setAVPlaybackState(this.currentState)
  }

  async pause():Promise<void>{
    this.localPlayOrPause()
    this.currentState = {
      state:this.isPlaying.get() ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
      position:{
        elapsedTime:this.currentTime,
        updateTime:new Date().getTime()
      }
    }
    await this.session?.setAVPlaybackState(this.currentState)
  }

  //开始长时任务
  async startCountinuousTask():Promise<void>{
    let wantAgentInfo:wantAgent.WantAgentInfo = {
      wants:[
        {
          bundleName:'com.example.musicplayerdemo',
          abilityName:'EntryAbility'
        }
      ],
      actionType:wantAgent.OperationType.START_ABILITY,
      requestCode:0,
      actionFlags:[wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    }
    let tmpWantAgent =  wantAgent.getWantAgent(wantAgentInfo)
    this.session?.setLaunchAbility(tmpWantAgent)
    backgroundTaskManager.startBackgroundRunning(MediaPlayer.instance.context,backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK, tmpWantAgent)
  }

  //关闭长时任务
  async stopContinuousTask():Promise<boolean>{
    return new Promise((resolve) => {
      backgroundTaskManager.stopBackgroundRunning(MediaPlayer.instance.context,(err,_) => {
        if (err) {
          resolve(false)
        }else {
          resolve(true)
        }
      })
    })
  }

}