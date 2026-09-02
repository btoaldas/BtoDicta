#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Ejecuta `bloque` atrapando cualquier NSException (que Swift NO puede capturar).
/// Devuelve nil si terminó bien, o "Nombre: razón" si hubo excepción.
/// Uso: audio (AVAudioEngine/AVAudioPlayerNode lanzan NSException al perder el
/// dispositivo de salida) — sin esto la app aborta entera.
FOUNDATION_EXPORT NSString * _Nullable BDAtraparExcepcion(void (NS_NOESCAPE ^bloque)(void));

NS_ASSUME_NONNULL_END
