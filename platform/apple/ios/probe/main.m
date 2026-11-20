#import <UIKit/UIKit.h>
#include <mach/mach.h>
#include <sys/mman.h>
#include <unistd.h>

@interface ProbeScene : UIResponder <UIWindowSceneDelegate>
@property(strong, nonatomic) UIWindow *window;
@end
@implementation ProbeScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    UIViewController *vc = [UIViewController new];
    self.window.rootViewController = vc;
    UITextView *view = [[UITextView alloc] initWithFrame:self.window.bounds];
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    view.editable = NO;
    [vc.view addSubview:view];
    [self.window makeKeyAndVisible];
    NSMutableString *report = [NSMutableString stringWithFormat:@"iOS native ARM64 probe\npage size %ld\n",sysconf(_SC_PAGESIZE)];
    uint64_t addresses[] = {0x7000000000ull,0x400000000ull,0x200000000ull};
    for (unsigned i = 0; i < sizeof addresses / sizeof addresses[0]; ++i) {
        vm_address_t address = addresses[i];
        kern_return_t status = vm_allocate(mach_task_self(), &address, 0x100000000ull, VM_FLAGS_FIXED);
        [report appendFormat:@"4GiB at 0x%llx: %s\n",addresses[i],mach_error_string(status)];
        if (status == KERN_SUCCESS) {
            int guarded = mprotect((void *)address, 0x100000000ull, PROT_NONE);
            int committed = mprotect((void *)(address+0x10000), 0x4000, PROT_READ|PROT_WRITE);
            if (!guarded && !committed) {
                *(volatile uint32_t *)(address+0x10000) = 0x12345678;
                [report appendFormat:@"guard/commit/read %s\n",*(volatile uint32_t *)(address+0x10000)==0x12345678? "PASS":"FAIL"];
            }
            vm_deallocate(mach_task_self(), address, 0x100000000ull);
        }
    }
    fprintf(stderr,"%s",report.UTF8String);
    view.text=report;
    return;
}
@end
@interface ProbeApp : UIResponder <UIApplicationDelegate>
@end
@implementation ProbeApp
- (UISceneConfiguration *)application:(UIApplication *)application
    configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options
{
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"UT3" sessionRole:session.role];
    configuration.delegateClass = ProbeScene.class;
    return configuration;
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {return UIApplicationMain(argc,argv,nil,NSStringFromClass(ProbeApp.class));}
}
