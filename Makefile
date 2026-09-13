APP = BtoDicta
BUILD_DIR ?= build
BUNDLE = $(BUILD_DIR)/$(APP).app
TRANSCRIBE_DIR ?= $(HOME)/transcribe.cpp
TRANSCRIBE_BUILD ?= $(TRANSCRIBE_DIR)/build

all: bundle

SOURCES := $(wildcard Sources/BtoDicta/*.swift)

$(BUILD_DIR)/release/$(APP): $(SOURCES) Package.swift
	swift build -c release --build-path $(BUILD_DIR)

# Puente C de streaming local. Es un target explícito: `make bundle` sigue
# funcionando para quien no haya clonado transcribe.cpp, pero una actualización
# del motor puede reconstruirse de forma reproducible con `make bto-stream`.
.PHONY: bto-stream
bto-stream:
	@test -f "$(TRANSCRIBE_DIR)/include/transcribe.h" || \
		(echo "Falta $(TRANSCRIBE_DIR)"; exit 1)
	@test -f "$(TRANSCRIBE_BUILD)/src/libtranscribe.a" || \
		(echo "Primero compila transcribe.cpp estático en $(TRANSCRIBE_BUILD)"; exit 1)
	@test -f "$(TRANSCRIBE_BUILD)/ggml/src/libggml.a" \
		-a -f "$(TRANSCRIBE_BUILD)/ggml/src/libggml-cpu.a" \
		-a -f "$(TRANSCRIBE_BUILD)/ggml/src/ggml-metal/libggml-metal.a" \
		-a -f "$(TRANSCRIBE_BUILD)/ggml/src/libggml-base.a" || \
		(echo "Faltan bibliotecas estáticas de GGML en $(TRANSCRIBE_BUILD)"; exit 1)
	mkdir -p build/native
	/usr/bin/clang -O3 -DNDEBUG -std=c11 \
		-I"$(TRANSCRIBE_DIR)/include" -I"$(TRANSCRIBE_DIR)/ggml/include" \
		-c native/bto-stream.c -o build/native/bto-stream.o
	/usr/bin/c++ -O3 -DNDEBUG build/native/bto-stream.o \
		"$(TRANSCRIBE_BUILD)/src/libtranscribe.a" \
		"$(TRANSCRIBE_BUILD)/ggml/src/libggml.a" \
		"$(TRANSCRIBE_BUILD)/ggml/src/libggml-cpu.a" \
		-framework Accelerate \
		"$(TRANSCRIBE_BUILD)/ggml/src/ggml-metal/libggml-metal.a" \
		"$(TRANSCRIBE_BUILD)/ggml/src/libggml-base.a" \
		-lm -framework Foundation -framework Metal -framework MetalKit \
		-o build/native/bto-stream.nuevo
	@test -x build/native/bto-stream.nuevo
	mv build/native/bto-stream.nuevo native/bto-stream
	@echo "Puente listo: native/bto-stream"

bundle: $(BUILD_DIR)/release/$(APP)
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	cp $(BUILD_DIR)/release/$(APP) $(BUNDLE)/Contents/MacOS/
	cp Info.plist $(BUNDLE)/Contents/
	mkdir -p $(BUNDLE)/Contents/Resources
	cp -R Resources/ $(BUNDLE)/Contents/Resources/
	# Motores locales embarcados: la app instalada no depende de builds de dev
	mkdir -p $(BUNDLE)/Contents/Resources/bin
	@if [ -x native/bto-stream ]; then cp native/bto-stream $(BUNDLE)/Contents/Resources/bin/; fi
	@if [ -x $(HOME)/transcribe.cpp/build/bin/transcribe-cli ]; then \
		cp $(HOME)/transcribe.cpp/build/bin/transcribe-cli $(BUNDLE)/Contents/Resources/bin/; fi
	@if [ -x $(HOME)/llama.cpp-static/build/bin/llama-server ]; then \
		cp $(HOME)/llama.cpp-static/build/bin/llama-server $(BUNDLE)/Contents/Resources/bin/; fi
	@if [ -x $(HOME)/whisper.cpp/build/bin/whisper-cli ]; then \
		cp $(HOME)/whisper.cpp/build/bin/whisper-cli $(BUNDLE)/Contents/Resources/bin/; \
		cp $(HOME)/whisper.cpp/build/bin/whisper-server $(BUNDLE)/Contents/Resources/bin/; \
		cp $(HOME)/whisper.cpp/build/bin/libwhisper.1.dylib $(BUNDLE)/Contents/Resources/bin/; \
		cp $(HOME)/whisper.cpp/build/bin/libggml.0.dylib $(BUNDLE)/Contents/Resources/bin/; \
		cp $(HOME)/whisper.cpp/build/bin/libggml-cpu.0.dylib $(BUNDLE)/Contents/Resources/bin/; \
		cp $(HOME)/whisper.cpp/build/bin/libggml-blas.0.dylib $(BUNDLE)/Contents/Resources/bin/; \
		cp $(HOME)/whisper.cpp/build/bin/libggml-metal.0.dylib $(BUNDLE)/Contents/Resources/bin/; \
		cp $(HOME)/whisper.cpp/build/bin/libggml-base.0.dylib $(BUNDLE)/Contents/Resources/bin/; \
		install_name_tool -delete_rpath $(HOME)/whisper.cpp/build/bin $(BUNDLE)/Contents/Resources/bin/whisper-cli 2>/dev/null || true; \
		install_name_tool -delete_rpath $(HOME)/whisper.cpp/build/bin $(BUNDLE)/Contents/Resources/bin/whisper-server 2>/dev/null || true; \
		install_name_tool -add_rpath @executable_path $(BUNDLE)/Contents/Resources/bin/whisper-cli 2>/dev/null || true; \
		install_name_tool -add_rpath @executable_path $(BUNDLE)/Contents/Resources/bin/whisper-server 2>/dev/null || true; fi
	@IDENTITY=$$(security find-certificate -c "BetoDicta Self Signed" >/dev/null 2>&1 && echo "BetoDicta Self Signed" || echo "-"); \
	echo "Firmando con: $$IDENTITY"; \
	codesign --force --deep --sign "$$IDENTITY" $(BUNDLE)
	@echo "Listo: $(BUNDLE)"

# Instalador DMG (requiere: brew install create-dmg)
dmg: bundle
	@V=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist); \
	if [ -e "$(BUILD_DIR)/BtoDicta-$$V.dmg" ]; then echo "El DMG ya existe; usa otro BUILD_DIR para preservarlo."; exit 1; fi; \
	if [ "$${BTODICTA_DMG_HEADLESS:-0}" != 1 ] && \
	perl -e '$$SIG{ALRM}=sub{exit 1}; alarm 5; exec @ARGV' /usr/bin/osascript -e 'tell application "Finder" to get name of every disk' >/dev/null 2>&1 && \
	create-dmg \
		--volname "BtoDicta $$V" \
		--window-size 560 400 \
		--icon-size 110 \
		--icon "BtoDicta.app" 140 160 \
		--app-drop-link 420 160 \
		--add-file "LÉEME primero.txt" packaging/LEEME-primero.txt 280 300 \
		"$(BUILD_DIR)/BtoDicta-$$V.dmg" "$(BUNDLE)"; then \
		true; \
	else \
		echo "Generando DMG sin AppleScript (modo headless o Finder no disponible)…"; \
		rm -f "$(BUILD_DIR)/BtoDicta-$$V.dmg"; \
		create-dmg --skip-jenkins \
			--volname "BtoDicta $$V" \
			--app-drop-link 420 160 \
			--add-file "LÉEME primero.txt" packaging/LEEME-primero.txt 280 300 \
			"$(BUILD_DIR)/BtoDicta-$$V.dmg" "$(BUNDLE)" || exit 1; \
	fi; \
	echo "DMG listo: $(BUILD_DIR)/BtoDicta-$$V.dmg"

install: bundle
	rm -rf /Applications/$(APP).app
	ditto $(BUNDLE) /Applications/$(APP).app
	@echo "Instalado en /Applications/$(APP).app"

# macOS 26 puede asociar el ícono a la app que lanzó BtoDicta durante el
# desarrollo. Este mantenimiento no abre AppKit: respalda y elimina únicamente
# la referencia cruzada ec.bto.btodicta de una fila extranjera.
reparar-icono:
	@xcrun swift scripts/reparar-icono-barra.swift

probar-reparacion-icono:
	@xcrun swift scripts/reparar-icono-barra.swift --probar

# Flujo de desarrollo seguro: evita reinstalar sobre un proceso vivo, abre la
# app nueva y corrige la asociación que macOS 26 puede crear con la herramienta
# que lanzó el build (Codex/Terminal). No forma parte del DMG ni toca otras apps.
instalar-local:
	-killall $(APP)
	$(MAKE) install
	open -a /Applications/$(APP).app
	sleep 3
	$(MAKE) reparar-icono
	@echo "BtoDicta instalado, abierto y con la barra verificada"

clean:
	rm -rf build

# Publica release en GitHub con DMG versionado + estable (para el tap Homebrew:
# releases/latest/download/BtoDicta.dmg). Uso: make release
release: dmg
	@V=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist); \
	cp "build/BtoDicta-$$V.dmg" "build/BtoDicta.dmg"; \
	gh release create "v$$V" --title "BtoDicta $$V" \
		"build/BtoDicta-$$V.dmg" "build/BtoDicta.dmg" && \
	echo "Release v$$V publicado (con DMG estable para brew)"
