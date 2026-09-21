# Contrato — consulta de la bitácora por la API local (spec 009, RF-02)

La API local de BtoDicta vive en `http://127.0.0.1:8787`, solo en bucle local, y
hoy ofrece cuatro caminos: `/estado`, `/transcribir`, `/pulir` y `/navegador`.
Esta spec añade **uno**, con las mismas reglas que los demás.

## Lo que no cambia

- **Autenticación**: cabecera `Authorization: Bearer <token>`, nunca en la
  dirección. `/estado` sigue siendo el único que no pide token.
- **Formato de error**: `{"error": "<motivo>"}` con el código HTTP que toca.
- **Tope de cuerpo**: 1 MiB; por encima, `413`.
- **Solo bucle local**: no se expone fuera del equipo.

## Lo que se añade

### `POST /buscar`

Petición:

```json
{
  "palabras": "certificado firma electronica",
  "material": "todo",
  "desde": 1755648000,
  "hasta": 1758326400,
  "limite": 50
}
```

| Campo | Obligatorio | Qué es |
|---|---|---|
| `palabras` | sí | lo que se busca; menos de 2 caracteres se rechaza |
| `material` | no | `pantalla`, `audio` o `todo` (de fábrica `todo`) |
| `desde` / `hasta` | no | ventana de tiempo en segundos desde 1970; de fábrica, todo lo guardado |
| `limite` | no | máximo de resultados; de fábrica 50, tope 200 |

Respuesta `200`:

```json
{
  "encontrados": 3,
  "resultados": [
    {
      "instante": 1758200000,
      "material": "pantalla",
      "origen": "Microsoft Edge",
      "ruta": "https://ejemplo.test/articulo",
      "fragmento": "…el certificado de firma electrónica caduca…"
    }
  ]
}
```

Errores:

| Código | Cuándo |
|---|---|
| `400` | falta `palabras`, o tiene menos de 2 caracteres |
| `401` | sin token o con token inválido |
| `409` | la bitácora está apagada en los ajustes: no hay nada que consultar |
| `413` | cuerpo mayor de 1 MiB |

## Lo que el contrato NO promete

- **No devuelve el texto completo** de una anotación, solo un fragmento con el
  contexto. Quien quiera el resto abre la bitácora.
- **No ordena por fecha**, sino por relevancia; la ventana de tiempo acota, no
  ordena.
- **No busca por significado**, solo por palabras. Declarado fuera de alcance en
  la spec.

## Comprobación

| Qué | Cómo |
|---|---|
| Devuelve lo mismo que la aplicación | Misma consulta por las dos vías, resultados comparados |
| Rechaza sin token | Prueba negativa: sin cabecera y con token inválido → `401` |
| Rechaza una consulta de una letra | `400`, sin recorrer las anotaciones |
| No se expone fuera | Comprobación de que solo escucha en `127.0.0.1` |
