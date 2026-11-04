#import "SessionOwnershipPolicy.h"
#include <stdio.h>
#include <stdlib.h>

static SOPInput Home(void) {
    SOPInput input = {
        .macs = {
            {SOPOpen, SOPHome, YES, YES, 1},
            {SOPOpen, SOPHome, YES, NO, 2},
            {SOPOpen, SOPHome, YES, NO, 3}
        },
        .owner = 0,
        .manualRequest = SOPNoMac,
        .approvalValid = YES,
        .approvedMac = 0
    };
    return input;
}

static void Expect(SOPInput input, SOPAction a, SOPAction b, SOPAction c,
                   const char *label) {
    SOPAction expected[SOPMacCount] = {a, b, c};
    for (NSInteger i = 0; i < SOPMacCount; i++) {
        input.localMac = i;
        SOPAction actual = SessionOwnershipDecision(input);
        if (actual != expected[i]) {
            fprintf(stderr, "%s: Mac %ld expected %ld, got %ld\n",
                    label, (long)i, (long)expected[i], (long)actual);
            abort();
        }
    }
}

int main(void) {
    @autoreleasepool {
        SOPInput input = Home();
        Expect(input, SOPKeepConnection, SOPHold, SOPHold, "idle Open home owner");
        input.macs[0].connected = NO;
        Expect(input, SOPRequestSavedAuth, SOPHold, SOPHold, "same-owner recovery");
        input.approvalValid = NO;
        Expect(input, SOPHold, SOPHold, SOPHold, "cached owner is not approval");
        input.approvalValid = YES;
        input.approvedMac = 2;
        Expect(input, SOPHold, SOPHold, SOPHold, "approval for another target");

        input = Home();
        input.manualRequest = 1;
        input.approvedMac = 1;
        Expect(input, SOPHold, SOPRequestSavedAuth, SOPHold, "manual beats Open owner");
        input.macs[2].location = SOPAway;
        Expect(input, SOPHold, SOPRequestSavedAuth, SOPHold, "manual beats Away");
        input.macs[0].presence = SOPUnknown;
        input.macs[1].presence = SOPUnknown;
        Expect(input, SOPHold, SOPRequestSavedAuth, SOPHold, "manual during Unknown Presence");
        input.approvalValid = NO;
        Expect(input, SOPKeepConnection, SOPHold, SOPHold, "unavailable manual approval");

        input = Home();
        input.owner = 1;
        input.ownerSelectedManually = YES;
        input.macs[0].connected = NO;
        input.macs[1].connected = YES;
        input.macs[2].location = SOPAway;
        input.approvedMac = 1;
        Expect(input, SOPHold, SOPKeepConnection, SOPHold, "accepted manual selection persists");
        input.macs[1].connected = NO;
        Expect(input, SOPHold, SOPRequestSavedAuth, SOPHold, "manual owner recovers before Away");
        input.approvedMac = 2;
        Expect(input, SOPHold, SOPHold, SOPHold, "stale Away approval cannot reverse manual");
        input.manualRequest = 2;
        Expect(input, SOPHold, SOPHold, SOPRequestSavedAuth, "another explicit selection");
        input.manualRequest = 0;
        input.approvedMac = 0;
        Expect(input, SOPRequestSavedAuth, SOPHold, SOPHold, "no global first-wins rule");

        input = Home();
        input.macs[2].location = SOPAway;
        input.approvedMac = 2;
        Expect(input, SOPHold, SOPHold, SOPRequestSavedAuth, "Away beats Open home owner");
        input.macs[0].presence = SOPUnknown;
        input.macs[1].presence = SOPUnknown;
        Expect(input, SOPHold, SOPHold, SOPRequestSavedAuth, "Away home-presence exception");
        input.approvalValid = NO;
        Expect(input, SOPKeepConnection, SOPHold, SOPHold, "Away still requires approval");

        input = Home();
        input.owner = 2;
        input.macs[0].connected = NO;
        input.macs[2].location = SOPAway;
        input.macs[2].presence = SOPClosed;
        input.approvedMac = 0;
        Expect(input, SOPHold, SOPHold, SOPHold, "Away reservation blocks home handoff");
        input.manualRequest = 0;
        Expect(input, SOPRequestSavedAuth, SOPHold, SOPHold, "manual overrides reservation");
        input.manualRequest = SOPNoMac;
        input.macs[2].presence = SOPOpen;
        input.approvedMac = 2;
        Expect(input, SOPHold, SOPHold, SOPRequestSavedAuth, "Away reservation recovery");
        input.macs[2].presence = SOPQuit;
        input.macs[2].appRunning = NO;
        input.approvedMac = 1;
        Expect(input, SOPHold, SOPRequestSavedAuth, SOPHold, "normal Away quit releases reservation");

        input = Home();
        input.macs[0].presence = SOPClosed;
        input.approvedMac = 2;
        Expect(input, SOPHold, SOPHold, SOPRequestSavedAuth, "confirmed home lock releases");
        input.macs[0].presence = SOPQuit;
        input.macs[0].appRunning = NO;
        Expect(input, SOPHold, SOPHold, SOPRequestSavedAuth, "normal quit permits handoff");
        input.manualRequest = 0;
        input.approvedMac = 0;
        Expect(input, SOPKeepConnection, SOPHold, SOPHold, "do not relaunch deliberately quit app");

        input = Home();
        input.macs[0].presence = SOPUnknown;
        input.approvedMac = 2;
        Expect(input, SOPKeepConnection, SOPHold, SOPHold, "missing owner is not release");
        input.macs[0].presence = SOPOpen;
        input.macs[0].appRunning = NO;
        Expect(input, SOPKeepConnection, SOPHold, SOPHold, "app disappearance is not normal quit");

        input = Home();
        input.owner = SOPNoMac;
        input.macs[0].connected = NO;
        input.approvedMac = 2;
        Expect(input, SOPHold, SOPHold, SOPRequestSavedAuth, "initial most recent selection");
        input.macs[1].recentUse = 4;
        input.approvedMac = 1;
        Expect(input, SOPHold, SOPRequestSavedAuth, SOPHold, "recent use can select middle Mac");
        input.macs[1].recentUse = 3;
        input.approvedMac = 2;
        Expect(input, SOPHold, SOPHold, SOPHold, "equal recent-use observations defer");
        input.manualRequest = 2;
        Expect(input, SOPHold, SOPHold, SOPRequestSavedAuth, "manual resolves recent-use tie");
        input.manualRequest = SOPNoMac;
        input.macs[1].recentUse = 0;
        Expect(input, SOPHold, SOPHold, SOPHold, "unknown recent-use ordering defers");
        input.macs[1].presence = SOPUnknown;
        Expect(input, SOPHold, SOPHold, SOPHold, "unknown peer blocks home acquisition");
        input.macs[1].presence = SOPClosed;
        input.macs[0].presence = SOPClosed;
        input.macs[2].recentUse = 0;
        Expect(input, SOPHold, SOPHold, SOPRequestSavedAuth, "sole eligible needs no input order");
        input.macs[1].location = SOPLocationUnknown;
        Expect(input, SOPHold, SOPHold, SOPHold, "unknown location defers home selection");
        input.macs[1].location = SOPHome;
        input.macs[2].presence = SOPClosed;
        Expect(input, SOPHold, SOPHold, SOPHold, "all closed stays on Hold");
        input.macs[2].presence = SOPOpen;
        input.macs[2].appRunning = NO;
        Expect(input, SOPHold, SOPHold, SOPHold, "Open app absent is not eligible");

        // Approval unavailability is independent of presence, preference and request type.
        for (NSInteger owner = SOPNoMac; owner < SOPMacCount; owner++) {
            for (NSInteger request = SOPNoMac; request < SOPMacCount; request++) {
                for (NSUInteger mask = 0; mask < (1U << SOPMacCount); mask++) {
                    input = Home();
                    input.owner = owner;
                    input.manualRequest = request;
                    input.approvalValid = NO;
                    input.macs[2].location = SOPAway;
                    for (NSInteger i = 0; i < SOPMacCount; i++) {
                        input.macs[i].connected = (mask & (1U << i)) != 0;
                    }
                    Expect(input,
                           input.macs[0].connected ? SOPKeepConnection : SOPHold,
                           input.macs[1].connected ? SOPKeepConnection : SOPHold,
                           input.macs[2].connected ? SOPKeepConnection : SOPHold,
                           "unavailable approval preserves only existing connections");
                }
            }
        }
        puts("Session ownership policy cases passed.");
    }
    return 0;
}
