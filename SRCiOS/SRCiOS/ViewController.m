//
//  ViewController.m
//  SmartCar
//
//  Created by TianYuan on 2018/1/26.
//  Copyright © 2018年 SmartCar. All rights reserved.
//


//7E330103010002607E   开灯
//7E330102010002A47E 开蜂鸣器

#import "ViewController.h"
#import "GCDAsyncSocket.h"
#import "WebViewJavascriptBridge.h"

@interface ViewController ()

@property (weak, nonatomic) IBOutlet UILabel *tempNum;
@property (weak, nonatomic) IBOutlet UILabel *humiNum;

@property (strong, nonatomic) IBOutlet UITextView *textView;
@property (strong, nonatomic) GCDAsyncSocket *socket;
@property (assign, nonatomic) uint8_t *array;
@property (weak, nonatomic) IBOutlet UITextField *serverIP;

@property (weak, nonatomic) IBOutlet UITextField *serverPort;

@property (weak, nonatomic) IBOutlet UIButton *buzzerBtton;
@property (weak, nonatomic) IBOutlet UIButton *lightButton;

@property (strong ,nonatomic) NSThread *heartThread;

@property (assign, nonatomic) BOOL vehicleStatus_Buzzer;
@property (assign, nonatomic) BOOL vehicleStatus_Light;
@property (assign, nonatomic) NSUInteger temp;
@property (assign, nonatomic) NSUInteger humi;
@property (weak, nonatomic) IBOutlet UITextField *deviceIDLable;

@property WebViewJavascriptBridge* bridge;


@end

//经常改变的数据
static const unsigned char SRCDeviceID = 0x33;
static const unsigned char SRCCommunicationType = 0x01;

//0x01：上位机下发 0x02：下位机上传
static const unsigned char SRCDataSourceDown = 0x01;
static const unsigned char SRCDataSourceUp = 0x02;

static const unsigned char SRCDataLength = 9;
static const unsigned char SRCHeader = 0x7E;
static const unsigned char SRCTail = 0x7E;




@implementation ViewController

- (void)viewWillAppear:(BOOL)animated{
 
 [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(connectAction)name:UIApplicationWillEnterForegroundNotification object:nil];

}

- (void)viewDidDisappear:(BOOL)animated{

    [[NSNotificationCenter defaultCenter] removeObserver:self];

}

-(void)testwebview{
    
    
    UIWebView *webView = [[UIWebView alloc] initWithFrame:self.view.bounds];
    [self.view addSubview:webView];
    
    NSString *htmlPath = [[NSBundle mainBundle] pathForResource:@"test" ofType:@"html"];
    NSString *appHtml = [NSString stringWithContentsOfFile:htmlPath encoding:NSUTF8StringEncoding error:nil];
    NSURL *baseURL = [NSURL fileURLWithPath:htmlPath];
    [webView loadHTMLString:appHtml baseURL:baseURL];

    // 开启日志
      [WebViewJavascriptBridge enableLogging];
    
    // 给哪个webview建立JS与OjbC的沟通桥梁
    self.bridge = [WebViewJavascriptBridge bridgeForWebView:webView];
    [self.bridge setWebViewDelegate:self];
    
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.humi = 0;
    self.temp = 0;
    
    self.deviceIDLable.text = [NSString  stringWithFormat:@"%d",SRCDeviceID];

    [self testwebview];

    
    [self connectAction];
    
//    [self testchec];
    
    
    [self customerUIs];

    // Do any additional setup after loading the view, typically from a nib.
}

- (void)textViewAddText:(NSString *)text {
    //加上换行
    self.textView.text = [text stringByAppendingFormat:@"\n%@",_textView.text ];
}

- (void)disconnectAction {
    
    [_socket disconnect];
    
}

- (void)connectAction{
    
    if (![_socket isConnected]) {
        
        self.socket = [[GCDAsyncSocket alloc]initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
        //socket.delegate = self;
        NSError *err = nil;
        if(![_socket connectToHost:self.serverIP.text onPort:[self.serverPort.text intValue] error:&err])
        {
            [self textViewAddText:err.description];
        }else
        {
            [self textViewAddText:@"connect ..."];
            
        }
   
    }else{
        [self textViewAddText:@"has connected"];
    }
    
}
-(void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port
{
    [self textViewAddText:[NSString stringWithFormat:@"connect to  %@",host]];
    
    if (!self.heartThread) {
        self.heartThread = [[NSThread alloc] initWithTarget:self selector:@selector(sendHeartBeat) object:nil];
        [self.heartThread start];
        
    }
    
    [_socket readDataWithTimeout:-1 tag:0];
}
-(void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag
{
    
//    Byte *resverByte = (Byte *)[data bytes];
    NSString * newMessage = [self hexStringFromData:data];
    [self showData: newMessage];
    [self getVehicleData:data];
    
    [_socket readDataWithTimeout:-1 tag:0];
}


-(void)getVehicleData:(NSData *)data{
    
    if ([data length] == SRCDataLength) {
        
        Byte *carData = (Byte *)[data bytes];
        
        if ((carData[0]&0xff) == SRCHeader &&(carData[SRCDataLength -1]&0xff) == SRCTail) {
            
            
             unsigned char cData[SRCDataLength-3] = { carData[1] , carData[2] , carData[3] , carData[4] , carData[5] , carData[6] };
            
            int CRCSum = crc8_chk_value(cData,6);
            
            
//            for(int i=1; i<[data length]-2; i++){
//                CRCSum+=carData[i];
//            }
//            CRCSum = CRCSum -1;
            
            if ((carData[SRCDataLength-2]&0xff) != CRCSum ||(carData[4]&0xff) != SRCDataSourceUp) {
//            if ((carData[4]&0xff) != SRCDataSourceUp) {
                [self showData: @"check data error"];

                return;
            }
            
            [self getVehicleDataWithDeviceID: self.deviceIDLable.text.integerValue ComType: SRCCommunicationType Commond: carData[3] HightData:carData[5] LowData:carData[6] ];
        }
        
        
    }
}



-(void)getVehicleDataWithDeviceID: (Byte)deviceID  ComType: (Byte)comType Commond: (Byte)commond HightData:(Byte)hightData LowData: (Byte)lowData{
    
    switch (commond) {
        case 2:
            if (lowData == 0x02) {//开
                _vehicleStatus_Buzzer = true;
            }else if (lowData == 0x01){
                _vehicleStatus_Buzzer = false;
            }
            break;
        case 3:
            if (lowData == 0x02) {//开
                _vehicleStatus_Light = true;
            }else if (lowData == 0x01){
                _vehicleStatus_Light = false;
            }
            break;
        case 4:
            self.temp = hightData;
            self.humi = lowData;
            
            break;
        
        default:
            break;
    }
    
    [self customerUIs];
}

-(void)customerUIs{
    [self.lightButton setBackgroundImage:[UIImage imageNamed: _vehicleStatus_Light ? @"light_open":@"light_close"] forState:UIControlStateNormal];
    
    [self.buzzerBtton setBackgroundImage:[UIImage imageNamed: _vehicleStatus_Buzzer ?@"buzzer_open" : @"buzzer_colse"] forState:UIControlStateNormal];
    self.tempNum.text = [NSString stringWithFormat:@"温度：%lu",(unsigned long)self.temp];
    self.humiNum.text = [NSString stringWithFormat:@"湿度：%lu",(unsigned long)self.humi];
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err
{
    _socket = nil;
    [self.heartThread cancel];
    self.heartThread = nil;
    [self showData: @"connect error"];
    return ;
}


-(void)setVehicleData:(Byte)commond LowData:(Byte)lowData{
    if ([_socket isConnected] ) {
        unsigned char carData[SRCDataLength] = { SRCHeader, self.deviceIDLable.text.integerValue,SRCCommunicationType, commond, SRCDataSourceDown, 0x00, lowData, 0x00, SRCTail};
        
        

        unsigned char cutData[SRCDataLength-3] = { carData[1] , carData[2] , carData[3] , carData[4] , carData[5] , carData[6] };
        carData[SRCDataLength - 2] = crc8_chk_value(cutData,6);
        
        NSData *d1 = [NSData dataWithBytes:carData length:sizeof(carData)];
        
        [_socket writeData:d1 withTimeout:-1 tag:0];

        NSString *str =  [self hexStringFromData:d1];
        
        
        [self showData: str];
        
    } else {
        [self showData: @"REMOTE connect close"];
    }
  

}


-(void)showData:(NSString *)newMessage{
    
    NSDateFormatter  *dateformatter=[[NSDateFormatter alloc] init];
    [dateformatter setDateFormat:@"YYYY-MM-dd HH:mm:ss.SSS"];
    NSString *locationString=[dateformatter stringFromDate:[NSDate date]];
    
    [self textViewAddText:[NSString stringWithFormat:@"%@  %@",locationString, newMessage]];
    
    [_socket readDataWithTimeout:-1 tag:0];

}

- (NSString *)hexStringFromData:(NSData *)data
{
    NSAssert(data.length > 0, @"data.length <= 0");
    NSMutableString *hexString = [[NSMutableString alloc] init];
    const Byte *bytes = data.bytes;
    for (NSUInteger i=0; i<data.length; i++) {
        Byte value = bytes[i];
        Byte high = (value & 0xf0) >> 4;
        Byte low = value & 0xf;
        [hexString appendFormat:@"%x%x", high, low];
    }//for
    return hexString;
}

-(NSData *)dataFromHexString:(NSString *)hexString
{
    NSAssert((hexString.length > 0) && (hexString.length % 2 == 0), @"hexString.length mod 2 != 0");
    NSMutableData *data = [[NSMutableData alloc] init];
    for (NSUInteger i=0; i<hexString.length; i+=2) {
        NSRange tempRange = NSMakeRange(i, 2);
        NSString *tempStr = [hexString substringWithRange:tempRange];
        NSScanner *scanner = [NSScanner scannerWithString:tempStr];
        unsigned int tempIntValue;
        [scanner scanHexInt:&tempIntValue];
        [data appendBytes:&tempIntValue length:1];
    }
    return data;
}

- (NSData *)dataWithReverse:(NSData *)srcData
{

    NSUInteger byteCount = srcData.length;
    NSMutableData *dstData = [[NSMutableData alloc] initWithData:srcData];
    NSUInteger halfLength = byteCount / 2;
    for (NSUInteger i=0; i<halfLength; i++) {
        NSRange begin = NSMakeRange(i, 1);
        NSRange end = NSMakeRange(byteCount - i - 1, 1);
        NSData *beginData = [srcData subdataWithRange:begin];
        NSData *endData = [srcData subdataWithRange:end];
        [dstData replaceBytesInRange:begin withBytes:endData.bytes];
        [dstData replaceBytesInRange:end withBytes:beginData.bytes];
    }
    
    return dstData;
}

- (NSData *)byteFromUInt8:(uint8_t)val
{
    NSMutableData *valData = [[NSMutableData alloc] init];
    
    unsigned char valChar[1];
    valChar[0] = 0xff & val;
    [valData appendBytes:valChar length:1];
    
    return [self dataWithReverse:valData];
}

- (IBAction)clearBoard:(UIButton *)sender {
    self.textView.text =@"";
}


- (IBAction)buttonClickedAction:(UIButton *)sender {
    NSInteger sendertag = sender.tag;
    
    switch (sendertag) {
            
        case 2:
            [self  connectAction];
            break;
        case 3:
            [self  disconnectAction];
            break;
        case 9:
            [self setVehicleData:0x03 LowData: _vehicleStatus_Light ? 0x01 : 0x02];//灯光开
            break;
        case 10:
            [self setVehicleData:0x02 LowData: _vehicleStatus_Buzzer ? 0x01 : 0x02];//蜂鸣器开
            break;
            
        default:
            
            break;
    }
    

}


//心跳包
-(void)sendHeartBeat{
    //    Byte keep_alive_data[] = {0x7E,0x00,0x01,0x00,0x00,0x00,0x7E};
    [NSThread sleepForTimeInterval:5.0f];
    
    while (self.heartThread !=nil) {
        [NSThread sleepForTimeInterval:5.0f];
        
        dispatch_sync(dispatch_get_main_queue(), ^{
            //Update UI in UI thread here
            [self setVehicleData:0x00 LowData:0x00];
        });
    }
}

unsigned char crc8_chk_value(unsigned char *message, unsigned char len)
{
    uint crc;
    uint i;
    crc = 0;
    while(len--)
    {
        crc ^= *message++;
        for(i = 0;i < 8;i++)
        {
            if(crc & 0x01)
            {
                crc = (crc >> 1) ^ 0x8c;
            }
            else crc >>= 1;
        }
    }
    return crc;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
