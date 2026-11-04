#import "SessionNetworkGate.h"
#import <objc/runtime.h>
#include <errno.h>
#include <libproc.h>
#include <stdatomic.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <unistd.h>

static atomic_bool networkHeld;
static NSHashTable<NSURLSession *> *sessions;
static NSHashTable<NSURLSessionTask *> *pausedTasks;
static NSMutableSet<NSValue *> *hookedClasses;

BOOL SessionNetworkGateIsHeld(void) { return atomic_load(&networkHeld); }
static BOOL InternetAddress(const struct sockaddr *address) {
    return address && (address->sa_family == AF_INET || address->sa_family == AF_INET6);
}
static BOOL HeldInternetSocket(int fd) {
    if (!SessionNetworkGateIsHeld()) return NO;
    struct sockaddr_storage address = {0};
    socklen_t size = sizeof(address);
    return getsockname(fd, (struct sockaddr *)&address, &size) == 0 &&
        InternetAddress((struct sockaddr *)&address);
}
static int GateConnect(int fd, const struct sockaddr *address, socklen_t size) {
    if (SessionNetworkGateIsHeld() && InternetAddress(address)) { errno = ENETDOWN; return -1; }
    return connect(fd, address, size);
}
static int GateConnectX(int fd, const sa_endpoints_t *endpoints, sae_associd_t association,
                        unsigned int flags, const struct iovec *iov, unsigned int count,
                        size_t *length, sae_connid_t *connection) {
    if (SessionNetworkGateIsHeld() && endpoints && InternetAddress(endpoints->sae_dstaddr)) {
        errno = ENETDOWN; return -1;
    }
    return connectx(fd, endpoints, association, flags, iov, count, length, connection);
}
static ssize_t GateSend(int fd, const void *data, size_t size, int flags) {
    if (HeldInternetSocket(fd)) { errno = ENETDOWN; return -1; }
    return send(fd, data, size, flags);
}
static ssize_t GateSendTo(int fd, const void *data, size_t size, int flags,
                          const struct sockaddr *address, socklen_t length) {
    if (HeldInternetSocket(fd) || (SessionNetworkGateIsHeld() && InternetAddress(address))) {
        errno = ENETDOWN; return -1;
    }
    return sendto(fd, data, size, flags, address, length);
}
static ssize_t GateSendMsg(int fd, const struct msghdr *message, int flags) {
    if (HeldInternetSocket(fd) || (SessionNetworkGateIsHeld() && message &&
        InternetAddress(message->msg_name))) { errno = ENETDOWN; return -1; }
    return sendmsg(fd, message, flags);
}
static ssize_t GateWrite(int fd, const void *data, size_t size) {
    if (HeldInternetSocket(fd)) { errno = ENETDOWN; return -1; }
    return write(fd, data, size);
}
static ssize_t GateWriteV(int fd, const struct iovec *iov, int count) {
    if (HeldInternetSocket(fd)) { errno = ENETDOWN; return -1; }
    return writev(fd, iov, count);
}
#define INTERPOSE(replacement, original) \
    __attribute__((used, section("__DATA,__interpose"))) \
    static const struct { const void *newFunction; const void *oldFunction; } \
    interpose_##original = {(const void *)replacement, (const void *)original}
INTERPOSE(GateConnect, connect);
INTERPOSE(GateConnectX, connectx);
INTERPOSE(GateSend, send);
INTERPOSE(GateSendTo, sendto);
INTERPOSE(GateSendMsg, sendmsg);
INTERPOSE(GateWrite, write);
INTERPOSE(GateWriteV, writev);

static void PauseTask(NSURLSessionTask *task) {
    @synchronized (pausedTasks) {
        if ([pausedTasks containsObject:task]) return;
        [pausedTasks addObject:task];
        if (task.state == NSURLSessionTaskStateRunning) [task suspend];
    }
}
static void HookTaskResumeMethods(void) {
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    for (unsigned int i = 0; i < count; i++) {
        Class cls = classes[i], parent = cls;
        while (parent && parent != NSURLSessionTask.class) parent = class_getSuperclass(parent);
        if (!parent) continue;
        NSValue *key = [NSValue valueWithPointer:(__bridge const void *)cls];
        if ([hookedClasses containsObject:key]) continue;
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(cls, &methodCount);
        for (unsigned int j = 0; j < methodCount; j++) {
            Method method = methods[j];
            if (method_getName(method) != @selector(resume) ||
                method_getNumberOfArguments(method) != 2) continue;
            IMP original = method_getImplementation(method);
            IMP replacement = imp_implementationWithBlock(^(NSURLSessionTask *task) {
                if (SessionNetworkGateIsHeld()) { PauseTask(task); return; }
                ((void (*)(id, SEL))original)(task, @selector(resume));
            });
            method_setImplementation(method, replacement);
        }
        free(methods);
        [hookedClasses addObject:key];
    }
    free(classes);
}
static void TrackSession(NSURLSession *session) {
    if (!session) return;
    @synchronized (sessions) { [sessions addObject:session]; }
}
void SessionNetworkGateInstall(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sessions = [NSHashTable weakObjectsHashTable];
        pausedTasks = [NSHashTable weakObjectsHashTable];
        hookedClasses = [NSMutableSet set];
        Method factory = class_getClassMethod(NSURLSession.class,
            @selector(sessionWithConfiguration:delegate:delegateQueue:));
        IMP original = method_getImplementation(factory);
        method_setImplementation(factory, imp_implementationWithBlock(
            ^NSURLSession *(id cls, NSURLSessionConfiguration *configuration,
                            id delegate, NSOperationQueue *queue) {
                NSURLSession *session = ((id (*)(id, SEL, id, id, id))original)(cls,
                    @selector(sessionWithConfiguration:delegate:delegateQueue:),
                    configuration, delegate, queue);
                TrackSession(session);
                return session;
            }));
        TrackSession(NSURLSession.sharedSession);
        HookTaskResumeMethods();
    });
}
void SessionNetworkGateSetHeld(BOOL held) {
    SessionNetworkGateInstall();
    if (atomic_exchange(&networkHeld, held) == (bool)held) return;
    if (!held) {
        NSArray<NSURLSessionTask *> *tasks;
        @synchronized (pausedTasks) {
            tasks = pausedTasks.allObjects;
            [pausedTasks removeAllObjects];
        }
        for (NSURLSessionTask *task in tasks)
            if (task.state == NSURLSessionTaskStateSuspended) [task resume];
        return;
    }
    HookTaskResumeMethods();
    NSArray<NSURLSession *> *knownSessions;
    @synchronized (sessions) { knownSessions = sessions.allObjects; }
    for (NSURLSession *session in knownSessions) {
        [session getAllTasksWithCompletionHandler:^(NSArray<NSURLSessionTask *> *tasks) {
            if (!SessionNetworkGateIsHeld()) return;
            for (NSURLSessionTask *task in tasks)
                if (task.state == NSURLSessionTaskStateRunning) PauseTask(task);
        }];
    }
    int bytes = proc_pidinfo(getpid(), PROC_PIDLISTFDS, 0, NULL, 0);
    if (bytes <= 0) return;
    struct proc_fdinfo *fds = calloc(1, (size_t)bytes);
    if (!fds) return;
    int actual = proc_pidinfo(getpid(), PROC_PIDLISTFDS, 0, fds, bytes);
    for (int i = 0; actual > 0 && i < actual / (int)sizeof(*fds); i++) {
        if (fds[i].proc_fdtype == PROX_FDTYPE_SOCKET && HeldInternetSocket(fds[i].proc_fd))
            shutdown(fds[i].proc_fd, SHUT_RDWR);
    }
    free(fds);
}
