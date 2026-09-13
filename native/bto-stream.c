// bto-stream — puente de streaming STT para BtoDicta.
//
// Lee PCM crudo (int16 LE, 16 kHz, mono) por STDIN y emite el transcript
// por STDOUT, una línea JSON por actualización:
//
//     READY                                  ← modelo cargado, listo para audio
//     {"c":"texto firme","t":"tentativo"}    ← tras cada cambio del resultado
//     {"f":"texto final"}                    ← al cerrar stdin (finalize)
//
// Uso:  bto-stream modelo.gguf es-US [chunk_ms=500]
//
// Motor: transcribe.cpp (handy-computer) — modelos streaming cache-aware
// como nemotron-3.5-asr-streaming (multilingüe) o moonshine-streaming.
// Compilar: ver Makefile (target bto-stream), linkea contra el build
// estático de ~/transcribe.cpp.

#include "transcribe.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Imprime una cadena escapada como JSON (sin las comillas envolventes).
static void json_escape(const char * s) {
    if (s == NULL) {
        return;
    }
    for (const unsigned char * p = (const unsigned char *) s; *p; ++p) {
        switch (*p) {
            case '"':  fputs("\\\"", stdout); break;
            case '\\': fputs("\\\\", stdout); break;
            case '\n': fputs("\\n", stdout); break;
            case '\r': fputs("\\r", stdout); break;
            case '\t': fputs("\\t", stdout); break;
            default:
                if (*p < 0x20) {
                    fprintf(stdout, "\\u%04x", *p);
                } else {
                    fputc(*p, stdout);
                }
        }
    }
}

static void emit_partial(struct transcribe_session * session) {
    struct transcribe_stream_text text;
    transcribe_stream_text_init(&text);
    if (transcribe_stream_get_text(session, &text) != TRANSCRIBE_OK) {
        return;
    }
    fputs("{\"c\":\"", stdout);
    json_escape(text.committed_text);
    fputs("\",\"t\":\"", stdout);
    json_escape(text.tentative_text);
    fputs("\"}\n", stdout);
    fflush(stdout);
}

int main(int argc, char ** argv) {
    if (argc < 3 || argc > 4) {
        fprintf(stderr, "uso: %s modelo.gguf idioma [chunk_ms=500]\n", argv[0]);
        return 2;
    }
    const char * model_path = argv[1];
    const char * language   = argv[2];
    const int    chunk_ms   = (argc == 4) ? atoi(argv[3]) : 500;
    if (chunk_ms <= 0 || chunk_ms > 5000) {
        fprintf(stderr, "error: chunk_ms fuera de rango\n");
        return 2;
    }

    struct transcribe_session * session = NULL;
    transcribe_status st = transcribe_open(model_path, NULL, NULL, &session);
    if (st != TRANSCRIBE_OK) {
        fprintf(stderr, "error: open: %s\n", transcribe_status_string(st));
        return 1;
    }

    struct transcribe_capabilities caps;
    transcribe_capabilities_init(&caps);
    if (transcribe_model_get_capabilities(transcribe_get_model(session), &caps) != TRANSCRIBE_OK ||
        !caps.supports_streaming) {
        fprintf(stderr, "error: el modelo no soporta streaming\n");
        transcribe_session_free(session);
        return 1;
    }

    struct transcribe_run_params run;
    transcribe_run_params_init(&run);
    // "auto" = dejar que el modelo detecte (Voxtral Realtime solo soporta
    // auto-detección; Nemotron exige idioma explícito tipo es-US).
    if (strcmp(language, "auto") != 0) {
        run.language = language;
    }

    st = transcribe_stream_begin(session, &run, NULL);
    if (st != TRANSCRIBE_OK) {
        fprintf(stderr, "error: stream_begin: %s\n", transcribe_status_string(st));
        transcribe_session_free(session);
        return 1;
    }

    fputs("READY\n", stdout);
    fflush(stdout);

    // Chunks de PCM int16 → float32. fread bloquea hasta llenar el chunk,
    // así que el ritmo lo marca quien escribe (la app, en vivo).
    const int chunk_samples = chunk_ms * 16000 / 1000;
    short *   pcm16         = malloc((size_t) chunk_samples * sizeof(short));
    float *   pcm32         = malloc((size_t) chunk_samples * sizeof(float));
    if (!pcm16 || !pcm32) {
        fprintf(stderr, "error: sin memoria\n");
        transcribe_session_free(session);
        return 1;
    }

    for (;;) {
        size_t got = fread(pcm16, sizeof(short), (size_t) chunk_samples, stdin);
        if (got == 0) {
            break;   // EOF: la app cerró el audio
        }
        for (size_t i = 0; i < got; ++i) {
            pcm32[i] = (float) pcm16[i] / 32768.0f;
        }
        struct transcribe_stream_update upd;
        transcribe_stream_update_init(&upd);
        st = transcribe_stream_feed(session, pcm32, (int) got, &upd);
        if (st != TRANSCRIBE_OK) {
            fprintf(stderr, "error: feed: %s\n", transcribe_status_string(st));
            break;
        }
        if (upd.result_changed) {
            emit_partial(session);
        }
    }

    if (st == TRANSCRIBE_OK) {
        struct transcribe_stream_update fin;
        transcribe_stream_update_init(&fin);
        st = transcribe_stream_finalize(session, &fin);
        if (st == TRANSCRIBE_OK) {
            struct transcribe_stream_text text;
            transcribe_stream_text_init(&text);
            if (transcribe_stream_get_text(session, &text) == TRANSCRIBE_OK && text.full_text) {
                fputs("{\"f\":\"", stdout);
                json_escape(text.full_text);
                fputs("\"}\n", stdout);
                fflush(stdout);
            }
        } else {
            fprintf(stderr, "error: finalize: %s\n", transcribe_status_string(st));
        }
    }

    free(pcm16);
    free(pcm32);
    transcribe_session_free(session);
    return (st == TRANSCRIBE_OK) ? 0 : 1;
}
