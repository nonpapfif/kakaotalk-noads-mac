#import <Foundation/Foundation.h>
#include <arpa/inet.h>
#include <dlfcn.h>
#include <errno.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <unistd.h>

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSCAssert(argc == 2, @"loopback test server port");
        void (*install)(void) = dlsym(RTLD_DEFAULT, "SessionNetworkGateInstall");
        void (*held)(BOOL) = dlsym(RTLD_DEFAULT, "SessionNetworkGateSetHeld");
        NSCAssert(install && held, @"gate dylib loaded at process launch");
        install();
        struct sockaddr_in address = {0};
        address.sin_len = sizeof(address); address.sin_family = AF_INET;
        address.sin_port = htons((uint16_t)atoi(argv[1]));
        address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        int existing = socket(AF_INET, SOCK_STREAM, 0);
        NSCAssert(connect(existing, (struct sockaddr *)&address, sizeof(address)) == 0,
                  @"normal connection allowed");
        held(YES);
        NSCAssert(send(existing, "x", 1, 0) == -1 && errno == ENETDOWN,
                  @"existing socket send blocked");
        NSCAssert(write(existing, "x", 1) == -1 && errno == ENETDOWN,
                  @"existing socket write blocked");
        struct iovec iov = {.iov_base = "x", .iov_len = 1};
        NSCAssert(writev(existing, &iov, 1) == -1 && errno == ENETDOWN,
                  @"existing socket writev blocked");
        int fresh = socket(AF_INET, SOCK_STREAM, 0);
        NSCAssert(connect(fresh, (struct sockaddr *)&address, sizeof(address)) == -1 &&
                  errno == ENETDOWN, @"new TCP connection blocked");
        int udp = socket(AF_INET, SOCK_DGRAM, 0);
        NSCAssert(sendto(udp, "x", 1, 0, (struct sockaddr *)&address, sizeof(address)) == -1 &&
                  errno == ENETDOWN, @"UDP send blocked");
        int local[2];
        NSCAssert(socketpair(AF_UNIX, SOCK_STREAM, 0, local) == 0, @"local socket pair");
        NSCAssert(write(local[0], "x", 1) == 1, @"local IPC remains usable");
        NSCAssert(recv(existing, &(char){0}, 1, 0) == 0, @"existing connection shut down");
        NSURLSession *session = [NSURLSession sessionWithConfiguration:
            NSURLSessionConfiguration.ephemeralSessionConfiguration];
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        __block BOOL succeeded = NO;
        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:
            @"http://127.0.0.1:%s/", argv[1]]];
        NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:
            ^(NSData *data, NSURLResponse *response, NSError *error) {
                (void)response;
                succeeded = !error && data.length > 0;
                dispatch_semaphore_signal(done);
            }];
        [task resume];
        NSCAssert(task.state == NSURLSessionTaskStateSuspended,
                  @"URLSession request remains suspended during Hold");
        held(NO);
        NSCAssert(connect(fresh, (struct sockaddr *)&address, sizeof(address)) == 0,
                  @"manual release permits new connection");
        close(existing); close(fresh); close(udp); close(local[0]); close(local[1]);
        NSCAssert(dispatch_semaphore_wait(done,
                  dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)) == 0 && succeeded,
                  @"URLSession request resumes after manual release");
        [session finishTasksAndInvalidate];
        puts("Network gate loopback checks passed.");
    }
}
