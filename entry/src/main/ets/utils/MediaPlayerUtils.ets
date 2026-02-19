import { common } from "@kit.AbilityKit"
import { media } from "@kit.MediaKit"
import { resourceManager } from "@kit.LocalizationKit"

//播放状态枚举类
/**
 * MediaPlayer 类是一个适配器（Adapter）或包装器（Wrapper），它将底层 AVPlayer 的 API 和复杂性进行了封装，对外提供了一个更高级、更易管理、更健壮的接口，供 ProviderFeature 这样的业务层代码使用
 */
export enum AVPlayerState {
  //闲置状态
  IDLE = 'idle',
  //初始化状态
  INITIALIZED = 'initialized',
  //准备状态
  PREPARED = 'prepared',
  //播放中
  PLAYING = 'playing',
  //暂停状态
  PAUSED = 'paused',
  //完成状态
  COMPLETED = 'completed',
  //停止状态
  STOPPED = 'stopped',
  //释放资源
  RELEASED = 'released'

}

/**
 * 工具类，封装AVPlayer的复杂操作，提供简介接口给业务层使用
 * 采用饿汉式单例模式，确保全局只有一个AVPlayer实例
 */
export default class MediaPlayer {
  //公共静态实例，在类定义时就创建（饿汉式）
  public static instance: MediaPlayer = new MediaPlayer()
  //上下文，由外部（如UIAbility）注入
  public context?: common.UIAbilityContext
  public avPlayer?: media.AVPlayer
  //播放状态
  public state: string = ''
  //用于储存异步回调的映射表
  private callbackMap: Record<string, object | null> = {}

  //私有构造函数，防止外部直接new
  private constructor() {
  }

  // /**
  //  * 获取单例实例
  //  * @returns MediaPlayer的唯一实例
  //  */
  // public static getInstance(): MediaPlayer {
  //   if (!MediaPlayer.instance) {
  //     //只有在第一次获取时才创建实例
  //     MediaPlayer.instance = new MediaPlayer()
  //   }
  //   return MediaPlayer.instance
  // }

  /**
   * 设置应用上下文
   * @param context UIAbility的上下文
   */
  public setContext(context: common.UIAbilityContext) {
    this.context = context
  }

  /**
   * 初始化AVPlayer实例并设置监听器
   * @returns 初始化后的AVPlayer实例
   */
  public async init(): Promise<media.AVPlayer | undefined> {
    if (!this.context) {
      console.error("MediaPlayer: Context is not set. Please call setContext first.")
      return undefined
    }
    try {
      this.avPlayer = await media.createAVPlayer()
      this.setAVPlayerCallback() //注册监听器
    } catch (error) {
      console.error("Failed to create AVPlayer:", error)
      return undefined

    }
    return this.avPlayer //返回实例，但调用者应检查返回值是否为undefined
  }

  //设置播放状态监听
  private setAVPlayerCallback() { // 将方法改为 private，因为它是内部实现细节
    if (!this.avPlayer) {
      console.warn("setAVPlayerListener: avPlayer is not initialized.")
      return
    }

    //在AVPlayer中，有两个必要事件，分别是stateChange和error这两个必须要设置监听
    //stateChange监听
    this.avPlayer?.on("stateChange", async (state: string, reason: media.StateChangeReason) => {
      //实时获取当前状态，将状态值赋给准备好的状态字段
      this.state = state
      switch (state) {
        case AVPlayerState.IDLE: // 闲置时
          console.info('idle')
          //闲置时把callbackMap清空
          this.callbackMap = {}
          break
        case AVPlayerState.INITIALIZED: // 初始化
          console.info('initialized')
          try {
            //初始化完成后，准备播放器
            await this.avPlayer?.prepare()
          } catch (error) {
            // TODO: Implement error handling.
            console.error("Failed to prepare AVPlayer after initialization:", error)
          }
          break
        case AVPlayerState.PREPARED:
          console.info('prepared')
          //检查是否有为'prepared'状态注册的回调
          if (this.callbackMap[AVPlayerState.PREPARED]) {
            let callbackPre: Function = this.callbackMap[AVPlayerState.PREPARED] as Function
            //执行
            if (callbackPre && typeof callbackPre === 'function') {
              callbackPre()
            }
            //执行完后清空,避免重复执行
            this.callbackMap[AVPlayerState.PREPARED] = null
          }
          break
        case AVPlayerState.PLAYING:
          console.log('playing')
          break
        case AVPlayerState.PAUSED:
          console.log('paused')
          break
        case AVPlayerState.COMPLETED:
          console.log('completed')
          break
        case AVPlayerState.STOPPED:
          console.log('stopped')
          break
        case AVPlayerState.RELEASED:
          console.log('released')
          break
        case 'error':
          console.log('error')
          break
        default:
          console.info('unknown状态')
          break
      }
    })
    //error监听
    this.avPlayer?.on('error', (err) => {
      //出现问题，没有什么是重启/重置解决不了的
      this.avPlayer?.reset()
      //可以调用reset重置，也可以第哦啊用release释放资源
    })
    /**
     * seekDone监听
     * 除了两个必要时间外，通常还会设置一个seekDone事件监听，实现进度跳转，该事件会在AVPlayer实例中调用seek方法（跳转方法）时触发
     * seekDoneTime:当前的time位/请求位，是要跳转的位置
     */
    this.avPlayer?.on('seekDone', (seekDoneTime: number) => {
      //seekDone事件回调中会获取用户请求的time位（跳转到的事件）
      //注意：在调用seek方法实现跳转时，由于seek方法需要设置一个叫做seekMode的参数，会造成实际跳转位置与用户设置产生偏差
      //如果需要获取准确事件，还需要在AVPlayer中调用currentTime
    })
  }

  /**
   * 添加指定事件的回调函数
   * @param event 事件名
   * @param callback 回调函数
   */
  onCallback(event: string, callback: Function) {
    this.callbackMap[event] = callback
  }

  //声明一个loadFromRawFile方法用于设置avplayer的播放资源，参数fileName就是需要播放的资源文件名
  /**
   * 加载rawfile目录下的音频文件
   * @param fileName rawfile 目录下的文件名
   */
  public async loadFromRawFile(fileName: string) {
    //判断是否有获取到avplayer实例
    if (!this.avPlayer || !this.context) {
      console.error("loadFromRawFile: avPlayer or context is not initialized.")
      return
    }
    //判断实例的播放状态，只有闲置状态才能设置播放资源
    //如果当前状态不是IDLE，需重置
    if (this.state !== AVPlayerState.IDLE) {
      //异步主要是为了reset重置准备的
      try {
        await this.avPlayer.reset()
        this.state = AVPlayerState.IDLE //重置后状态变为IDLE
      } catch (error) {
        // TODO: Implement error handling.
        console.error("Failed to reset AVPlayer before loading new file:", error)
        // 重置失败，可能无法加载新文件，视情况处理
        return
      }
    }


    try {
      //这里采用音视频文件资源描述的方式设置播放资源
      //音视频文件资源描述，一种特殊资源的播放方式，使用场景：应用中的音频资源被连续存储在同一个文件中，需要根据偏移量和长度进行播放。
      //声明一个常量，做临时存储，存获取到的文件的描述符
      //getRawFd()用于获取放置在resource/rawfile目录下的文件的描述符
      const fileDescriptor: resourceManager.RawFileDescriptor | undefined = this.context!.resourceManager.getRawFdSync(fileName)

      //如果获取到了，就把fileDescriptor，转换成avFileDescriptor
      if (fileDescriptor) {
        let avFileDescriptor: media.AVFileDescriptor = {
          fd: fileDescriptor.fd,
          offset: fileDescriptor.offset,
          length: fileDescriptor.length
        }
        //最后把转换好的avFileDescriptor，赋值给avPlayer
        //设置播放源
        this.avPlayer.fdSrc = avFileDescriptor
      } else {
        console.error(`loadFromRawFile: Failed to get file descriptor for ${fileName}`)
      }
    } catch (error) {
      console.error('getEawFd fail', error)
    }
  }

  /**
   * 释放AVPlayer资源
   */
  public release(){
    if (this.avPlayer) {
      this.avPlayer.release(() => {
        console.info("AVPlayer released successfully.")
      })
      this.avPlayer = undefined //清空引用
      this.state = '' //清空状态
    }
  }

}
