//
//  ZZWebViewController.m
//  YUNDADA
//
//  Created by CHAT on 2018/7/30.
//  Copyright © 2018年 yundada. All rights reserved.
//

#import "ZZWebViewController.h"
#import <dsbridge.h>
#import "ZZApiForJs.h"
#import "ZWHTMLSDK.h"
#import <WebKit/WebKit.h>
#import <UIScrollView+EmptyDataSet.h>
#import <ZZRoutePageHandler.h>
#import "UIViewController+ZZBackButton.h"
#import "ZZRemoteGlobalConfig.h"

@interface ZZPhoneCallInfoFromH5 :NSObject
@property (nonatomic , copy) NSString              * type;
@property (nonatomic , copy) NSString              * id;
@property (nonatomic , copy) NSString              * destination;
@property (nonatomic , copy) NSString              * origin;

@end

@implementation ZZPhoneCallInfoFromH5

@end

@interface ZZWebViewController ()<WKNavigationDelegate, DZNEmptyDataSetSource, DZNEmptyDataSetDelegate, ZZRoutePageHandlerProtocol, WKUIDelegate>

@property (nonatomic, strong) ZWHTMLSDK *htmlSDK;

//给h5通话记录使用
@property (nonatomic, strong) ZZPhoneCallInfoFromH5* phoneCallInfo;
@property (nonatomic) BOOL needRefreshPage;

@end

@implementation ZZWebViewController

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.autoChangeTitle = YES;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    CGRect bounds = self.view.bounds;
    
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    WKPreferences *preferences = [WKPreferences new];
    preferences.javaScriptCanOpenWindowsAutomatically = YES;//很重要，如果没有设置这个则不会回调createWebViewWithConfiguration方法，也不会回应window.open()方法
    config.preferences = preferences;

    DWKWebView *dwebview = [[DWKWebView alloc] initWithFrame:CGRectMake(0, 0, bounds.size.width, bounds.size.height-25) configuration:config];
    dwebview.scrollView.bouncesZoom = NO;
    dwebview.scrollView.bounces = NO;
    dwebview.navigationDelegate = self;
    dwebview.DSUIDelegate = self;
    self.webView = dwebview;
    [self.view addSubview:dwebview];
    
    [dwebview setInvocationCaptureBlock:^(NSString *method, NSString *arg) {
        NSMutableString *log = [NSMutableString string];
        [log appendFormat:@"\n==========> JSBridge method: %@ \n", method];
        [log appendFormat:@"  arg: %@ \n", arg];
        [log appendString:@"<====================="];
        ZZLogInfo(@"%@", log);
    }];
    
    if (self.transNavigationBar)
    {
        [dwebview mas_makeConstraints:^(MASConstraintMaker *make) {
            make.bottom.right.left.equalTo(@0);
            CGRect statusBarRect = [UIApplication sharedApplication].statusBarFrame;
            CGRect navBarRect = self.navigationController.navigationBar.frame;
            make.top.equalTo(@(-(statusBarRect.size.height+navBarRect.size.height)));
        }];
    }
    else
    {
        [dwebview mas_makeConstraints:^(MASConstraintMaker *make) {
            make.edges.mas_equalTo(UIEdgeInsetsZero);
        }];
    }
    
    [dwebview addJavascriptObject:[[ZZApiForJs alloc] initWithWebViewVC:self] namespace:@"user"];
    [dwebview addJavascriptObject:[[ZZApiForJs alloc] initWithWebViewVC:self] namespace:@"ui"];
    [dwebview addJavascriptObject:[[ZZApiForJs alloc] initWithWebViewVC:self] namespace:@"storage"];
    [dwebview addJavascriptObject:[[ZZApiForJs alloc] initWithWebViewVC:self] namespace:@"navigation"];
    [dwebview addJavascriptObject:[[ZZApiForJs alloc] initWithWebViewVC:self] namespace:@"pay"];
    
    //此处不要乱动，百度地图的h5页面校验UA
    self.webView.customUserAgent = @"Mozilla/5.0 (iPhone; CPU iPhone OS 11_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15F79/ydd";
//    [self.webView evaluateJavaScript:@"navigator.userAgent" completionHandler:^(NSString* result, NSError * _Nullable error) {
//        //1）获取默认userAgent：
//        NSString *oldUA = result;   //直接获取为nil ，需loadRequest
//        //2）设置userAgent：添加额外的信息
//        NSString* ClientInfo = [[ZZApiEngine sharedEngine] valueForKey:@"ClientInfo"]?:@"";
//        NSString *newUA =[NSString stringWithFormat:@"%@%@/ydd)", oldUA , ClientInfo];
//        self.webView.customUserAgent = newUA;
//    }];

    //监听网络加载进度
    [self.webView addObserver:self forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:nil];
    if (self.autoChangeTitle)
    {
        [self.webView addObserver:self forKeyPath:@"title" options:NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld context:nil];
    }
        
    [dwebview setDebugMode:true];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self beginLoadUrl];
    });
    
    //余额变动通知
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(freshPage:) name:ZZMoneyDidChangeResultNotification object:nil];
    //登录成功通知
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(beginLoadUrl) name:ZZLoginDidSuccessNotification object:nil];
    //退出登录通知
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(beginLoadUrl) name:ZZLogoutDidSuccessNotification object:nil];
    
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(freshPage:) name:ZZPublishPromotionSuccessNotification object:nil];
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(freshPage:) name:ZZRefreshWebviewNotification object:nil];
    
    self.webView.scrollView.emptyDataSetSource = self;
    self.webView.scrollView.emptyDataSetDelegate = self;
}

-(void) beginLoadUrl
{
    if ([self.url hasPrefix:@"http://"] ||
        [self.url hasPrefix:@"https://"] ||
        [self.url hasPrefix:@"file://"])
    {
        [self loadUrl:self.url];
    }
    else
    {
        if ([ZZRemoteGlobalConfig getInstance])
        {
            self.url = FullH5WithNormalPath(self.url);
            [self loadUrl:self.url];
        }
        else
        {
            [ZZRemoteGlobalConfig updateConfig:^(NSError *error) {
                self.url = FullH5WithNormalPath(self.url);
                [self loadUrl:self.url];
            }];
        }
    }
}

- (void)loadUrl:(NSString*)url
{
    ZZLogInfo(@"webview开始加载url：%@", url);
    if ([NSString isNilOrEmpty:url])
    {
        ZZLogInfo(@"webview的url格式错误");
        return;
    }
    NSURLComponents *urlComponents = [NSURLComponents componentsWithString:url];
    NSURL *localUrl = urlComponents.URL;
    if ([urlComponents.scheme isEqualToString:@"file"]) {
        [self.webView loadFileURL:localUrl allowingReadAccessToURL:localUrl];
    } else {
        __block BOOL isHasOrigin = NO;
        __block NSString *value = nil;
        [urlComponents.queryItems enumerateObjectsUsingBlock:^(NSURLQueryItem * _Nonnull queryItem, NSUInteger idx, BOOL * _Nonnull stop) {
            if([queryItem.name isEqualToString:@"origin"]){
                isHasOrigin = YES;
                value = queryItem.value;
                *stop = YES;
            }
        }];
        if(isHasOrigin && ![NSString isNilOrEmpty:value]){
            self.zz_origin = value;
        }
        [self.webView loadRequest:[NSURLRequest requestWithURL:localUrl]];
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    if (self.needRefreshPage)
    {
        [self.webView callHandler:@"onRefreshPage" arguments:@[]];
        self.needRefreshPage = NO;
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self freshNetworkTip];
    });
}

- (void)freshNetworkTip
{
    if (ZZNetworkStatusTypeDisconnect == [ZZReachability reachabilityForInternetConnection].currentNetStatusType)
    {
        [self.webView.scrollView reloadEmptyDataSet];
    }
}

-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.title = self.webView.title;
    self.alphaNavigationBar = YES;
    
    if (self.alphaNavigationBar)
    {
        [self.navigationController.navigationBar setBackgroundImage:[UIImage new] forBarMetrics:UIBarMetricsDefault];
        [self.navigationController.navigationBar setShadowImage:[UIImage new]];
    }
    
    if (self.transNavigationBar)
    {
        self.navigationController.navigationBar.translucent = YES;
    }
}

-(void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    if (self.alphaNavigationBar)
    {
        [self.navigationController.navigationBar setBackgroundImage:nil forBarMetrics:UIBarMetricsDefault];
        [self.navigationController.navigationBar setShadowImage:nil];
    }
    if (self.transNavigationBar)
    {
        self.navigationController.navigationBar.translucent = NO;
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context
{
    if ([keyPath isEqualToString:@"title"] && self==[ZZUIManager sharedUIManager].topViewController)
    {
        self.title = self.webView.title;
    }
    else if ([keyPath isEqualToString:@"estimatedProgress"]) {
        if (object == self.webView){
            self.progressView.alpha = 1;
            [self.progressView setProgress:self.webView.estimatedProgress animated:YES];
            if(self.webView.estimatedProgress >= 1.0f) {
                [UIView animateWithDuration:0.25f delay:0.3f options:UIViewAnimationOptionCurveEaseOut animations:^{
                    self.progressView.transform = CGAffineTransformMakeScale(1.0f, 1.4f);
                } completion:^(BOOL finished) {
                    [self.progressView setProgress:0.0f animated:NO];
                    self.progressView.hidden = YES;
                }];
            }
        }
    }
}

- (void)dealloc
{
    [self.webView removeObserver:self forKeyPath:@"estimatedProgress"];
    
    if (self.autoChangeTitle)
    {
        [self.webView removeObserver:self forKeyPath:@"title"];
    }
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)navigationShouldPopOnBackButton
{
    if (self.webView.canGoBack) {
        [self.webView goBack];
        return NO;
    } else {
        return YES;
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma -mark getter 网络加载 进度条
- (UIProgressView *)progressView {
    if (!_progressView){
        UIProgressView *progressView = [[UIProgressView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, 2)];
        progressView.tintColor = [UIColor greenColor];
        progressView.trackTintColor = [UIColor clearColor];
        //设置进度条的高度，下面这句代码表示进度条的宽度变为原来的1倍，高度变为原来的1.5倍.
        progressView.transform = CGAffineTransformMakeScale(1.0f, 1.5f);
        [self.view addSubview:progressView];
        _progressView = progressView;
    }
    return _progressView;
}

#pragma mark - UIDelegate
-(WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures{
    ZZLogInfo(@"createWebViewWithConfiguration  request     %@",navigationAction.request);
    if (!navigationAction.targetFrame.isMainFrame) {
        [webView loadRequest:navigationAction.request];
    }
    if (navigationAction.targetFrame == nil) {
        [webView loadRequest:navigationAction.request];
    }
    return nil;
}


#pragma mark - WKNavigationDelegate
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation
{
    ZZLogInfo(@"webView didFinishNavigation url>%@", webView.URL.absoluteString);
//    self.htmlSDK = [ZWHTMLSDK zw_loadBridgeJSWebview:webView withOption:nil];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
    ZZLogInfo(@"webView decidePolicyForNavigationAction url>%@", webView.URL.absoluteString);
    NSString * newPath = navigationAction.request.URL.scheme;
    if ([newPath hasPrefix:@"sms"] || [newPath hasPrefix:@"tel"]) {
        
        UIApplication * app = [UIApplication sharedApplication];
        if ([app canOpenURL:navigationAction.request.URL]) {
            [app openURL:navigationAction.request.URL];
        }
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    
    decisionHandler(WKNavigationActionPolicyAllow);
//    [self.htmlSDK zw_handlePreviewImageRequest:navigationAction.request];
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(null_unspecified WKNavigation *)navigation
{
    ZZLogInfo(@"webView didStartProvisionalNavigation url>%@", webView.URL.absoluteString);
    NSString * newPath = webView.URL.scheme;
    if ([newPath hasPrefix:@"sms"] || [newPath hasPrefix:@"tel"]) {
        
        UIApplication * app = [UIApplication sharedApplication];
        if ([app canOpenURL:webView.URL]) {
            [app openURL:webView.URL];
        }
        return;
    }
    
    //开始加载网页时展示出progressView
    self.progressView.hidden = NO;
    //开始加载网页的时候将progressView的Height恢复为1.5倍
    self.progressView.transform = CGAffineTransformMakeScale(1.0f, 1.5f);
    //防止progressView被网页挡住
    [self.view bringSubviewToFront:self.progressView];
}

//加载失败
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    ZZLogError(@"加载webView失败 url>%@ error>%@", webView.URL.absoluteString, error);
    //加载失败同样需要隐藏progressView
    self.progressView.hidden = YES;
}


- (void)setUrl:(NSString *)url
{
    if ([NSString isNilOrEmpty:url]) {
        _url = @"";
        ZZLogInfo(@"setUrl webview的url格式错误");
        return;
    }
    _url = url;
    NSURLComponents *comp = [NSURLComponents componentsWithString:url];
    NSURLQueryItem *item = [NSURLQueryItem queryItemWithName:@"version" value:[ZZDeviceUtils appVersion]];
    comp.queryItems = [comp.queryItems?:@[] arrayByAddingObjectsFromArray:@[item]];
    _url = comp.URL.absoluteString;
}

- (void)action_zzwebviewcontroller:(NSDictionary *)object{
    self.url = object[@"url"];
}

- (BOOL)handleViewControllerDataWithObject:(id)parameters {
    return YES;
}


#pragma -mark
- (void)freshPage:(id)sender {
    //原生调用js   用于刷新我的订单列表和订单详情（H5）
    if (self == UIManager.topViewController)
    {
        [self.webView callHandler:@"onRefreshPage" arguments:@[]];
        self.needRefreshPage = NO;
    }
    else
    {
        self.needRefreshPage = YES;
    }
}

#pragma - mark DZNEmptyDataSetSource
- (UIImage *)imageForEmptyDataSet:(UIScrollView *)scrollView
{
    return [UIImage imageNamed:@"image_network_err"];
}

- (NSAttributedString *)titleForEmptyDataSet:(UIScrollView *)scrollView
{
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.lineBreakMode = NSLineBreakByWordWrapping;
    paragraph.alignment = NSTextAlignmentCenter;
    
    NSDictionary *attributes = @{NSFontAttributeName: [UIFont systemFontOfSize:17.f],
                                              NSForegroundColorAttributeName: [UIColor lightGrayColor],
                                              NSParagraphStyleAttributeName: paragraph};
    
    return [[NSAttributedString alloc] initWithString:@"您还没有连接网络" attributes:attributes];
}

- (NSAttributedString *)buttonTitleForEmptyDataSet:(UIScrollView *)scrollView forState:(UIControlState)state
{
    NSDictionary *attributes = @{NSFontAttributeName: [UIFont systemFontOfSize:15.0f],
                                 NSForegroundColorAttributeName: ZZ_COLOR_BLUE
                                 };
    return [[NSAttributedString alloc] initWithString:@"点击刷新" attributes:attributes];
}

- (UIImage *)buttonBackgroundImageForEmptyDataSet:(UIScrollView *)scrollView forState:(UIControlState)state
{
    NSString *imageName = @"button_background_normal";
    UIEdgeInsets capInsets = UIEdgeInsetsMake(10.0, 10.0, 10.0, 10.0);
    CGFloat space = (scrollView.bounds.size.width - 150)/2.f;
    UIEdgeInsets rectInsets = UIEdgeInsetsMake(-19.0, -space, -19.0, -space);
    UIImage *image = [UIImage imageNamed:imageName inBundle:[NSBundle bundleForClass:[self class]] compatibleWithTraitCollection:nil];
    return [[image resizableImageWithCapInsets:capInsets resizingMode:UIImageResizingModeStretch] imageWithAlignmentRectInsets:rectInsets];
}

#pragma - mark DZNEmptyDataSetDelegate
- (BOOL)emptyDataSetShouldDisplay:(UIScrollView *)scrollView
{
    if (self.webView.isLoading)
    {
        return NO;
    }
    return YES;
}

- (void)emptyDataSet:(UIScrollView *)scrollView didTapButton:(UIButton *)button
{
    NSURL* url = self.webView.URL;
    if (url)
    {
        [self beginLoadUrl];
    }
    else
    {
        [self beginLoadUrl];
    }
    [self.webView.scrollView reloadEmptyDataSet];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self freshNetworkTip];
    });
}

#pragma mark - 通话记录相关
-(void) prepareH5PhoneCall:(NSDictionary*) phoneCallInfo
{
    self.phoneCallInfo = [ZZPhoneCallInfoFromH5 yy_modelWithJSON:phoneCallInfo[@"data"]];
    [ZZDeviceUtils callPhoneWithNumber:phoneCallInfo[@"phone"]];
}

static NSString* const CALL_TYPE_LINE = @"line";
static NSString* const CALL_TYPE_CARGO = @"cargo";
- (NSString *)lineId
{
    if (!self.phoneCallInfo)
    {
        return nil;
    }
    if ([self.phoneCallInfo.type isEqualToString:CALL_TYPE_LINE])
    {
        return self.phoneCallInfo.id;
    }
    return nil;
}

- (NSNumber *)destination
{
    if (!self.phoneCallInfo)
    {
        return nil;
    }
    if ([self.phoneCallInfo.type isEqualToString:CALL_TYPE_LINE])
    {
        return @(self.phoneCallInfo.destination.integerValue);
    }
    return nil;
}

- (NSString *)cargoId
{
    if (!self.phoneCallInfo)
    {
        return nil;
    }
    if ([self.phoneCallInfo.type isEqualToString:CALL_TYPE_CARGO])
    {
        return self.phoneCallInfo.id;
    }
    return nil;
}

- (NSString *)origin
{
    if (!self.phoneCallInfo)
    {
        return nil;
    }
    if ([self.phoneCallInfo.type isEqualToString:CALL_TYPE_CARGO])
    {
        return self.phoneCallInfo.origin;
    }
    return nil;
}


@end









