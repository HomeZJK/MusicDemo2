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
 * 工具类内部获取ui上下文
 */
export default class MediaPlayer {
  //获取唯一的avplayer实例
  static instance: MediaPlayer
  //上下文
  context?: common.UIAbilityContext
  avPlayer?: media.AVPlayer
  //播放状态
  state: string = ''
  callbackMap: Record<string, object | null> = {}

  //通过onCallback方法用于动态为callbackMap添加事件回调方法
  //这些方法会根据实际需求手动添加，用于avplayer播放状态监听的事件触发
  onCallback(event: string, callback: Function) {
    this.callbackMap[event] = callback
  }

  //设置播放状态监听
  setAVPlayerListener() {
    //在AVPlayer中，有两个必要事件，分别是stateChange和error这两个必须要设置监听
    //stateChange监听
    this.avPlayer?.on("stateChange", async (state: string, reason: media.StateChangeReason) => {
      //实时获取当前状态，将状态值赋给准备好的状态字段
      this.state = state
      switch (state) {
        case 'idle': // 闲置时
          console.info('idle')
          //闲置时把callbackMap清空
          this.callbackMap = {}
          break
        case 'initialized': // 初始化
          console.info('initialized')
          await this.avPlayer?.prepare()
          break
        case 'prepared':
          console.info('prepared')
          //判断在事件回调集合中是否添加了关于prepared状态的时间回调，如果有就执行，后续的状态转换判断中都可以通过该方式来设置是否有回调需要执行
          if (this.callbackMap[AVPlayerState.PREPARED]) {
            let callbackPre: Function = this.callbackMap[AVPlayerState.PREPARED] as Function
            //执行
            callbackPre()
            //执行完后清空
            this.callbackMap[AVPlayerState.PREPARED] = null
          }
          break
        case 'playing':
          console.log('playing')
          break
        case 'paused':
          console.log('paused')
          break
        case 'completed':
          console.log('completed')
          break
        case 'stopped':
          console.log('stopped')
          break
        case 'released':
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
    this.avPlayer?.on('seekDone', (seekDoneTime:number) => {
      //seekDone事件回调中会获取用户请求的time位（跳转到的事件）
      //注意：在调用seek方法实现跳转时，由于seek方法需要设置一个叫做seekMode的参数，会造成实际跳转位置与用户设置产生偏差
      //如果需要获取准确事件，还需要在AVPlayer中调用currentTime
    })
  }

  //声明一个loadFromRawFile方法用于设置avplayer的播放资源，参数fileName就是需要播放的资源文件名
  async loadFromRawFile(fileName:string){
    //判断是否有获取到avplayer实例
    if (!this.avPlayer) {
      return
    }
    //判断实例的播放状态，只有闲置状态才能设置播放资源
    if (this.state !== AVPlayerState.IDLE) {
      //异步主要是为了reset重置准备的
      await this.avPlayer.reset()
    }
    //结束这两个判断后，说明现在拿到了实例，且实例处在闲置状态
    //这里的实现方式不太一样，是通过try来实现的
    try{
      //这里采用音视频文件资源描述的方式设置播放资源
      //音视频文件资源描述，一种特殊资源的播放方式，使用场景：应用中的音频资源被连续存储在同一个文件中，需要根据偏移量和长度进行播放。
      //声明一个常量，做临时存储，存获取到的文件的描述符
      //getRawFd()用于获取放置在resource/rawfile目录下的文件的描述符
      const  fileDescriptor:resourceManager.RawFileDescriptor | undefined = await this.context?.resourceManager.getRawFd(fileName)

      //如果获取到了，就把fileDescriptor，转换成avFileDescriptor
      if (fileDescriptor) {
        let avFileDescriptor:media.AVFileDescriptor = {
          fd:fileDescriptor.fd,
          offset:fileDescriptor.offset,
          length:fileDescriptor.length
        }
        //最后把转换好的avFileDescriptor，赋值给avPlayer
        this.avPlayer.fdSrc = avFileDescriptor
      }else {
        console.error('fileDescriptor fail')
      }
    }catch (error){
      console.error('getEawFd fail')
    }
  }
  //声明init初始化方法，创建AVPlayer实例并开启监听
  async initial():Promise<media.AVPlayer | undefined>{
    try {
      //创建avplayer实例
      this.avPlayer = await media.createAVPlayer()
      //开监听
      this.setAVPlayerListener()
      //把实例return出去，谁要谁获取
      return this.avPlayer
    }catch (error){
      //不return undefined的话报错：Not all code paths return a value.
      return undefined
    }
  }

  //单例模式
  static getInstance():MediaPlayer{
    //判断有没有instance
    //注意：在类的内部访问自己的静态字段时不能使用this，因为this指向的是当前类的实例，实例对象是中是无法调用静态字段的
    //解释：这里的instance是静态属性，用this指不到，可以用类名.属性名给它点出来
    if (!MediaPlayer.instance) {
      //如果没有就创建一个
      MediaPlayer.instance = new MediaPlayer()
    }
    return MediaPlayer.instance
  }
}

