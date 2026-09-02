#import "BDTry.h"

NSString *BDAtraparExcepcion(void (NS_NOESCAPE ^bloque)(void)) {
    @try {
        bloque();
        return nil;
    } @catch (NSException *e) {
        return [NSString stringWithFormat:@"%@: %@", e.name, e.reason ?: @""];
    }
}
