# Copy&Paste

Aplicacion macOS de barra de menu para guardar, buscar y reutilizar el historial del portapapeles.

Copy&Paste permite abrir un historial rapido con `Command + Shift + V`, seleccionar un registro copiado previamente y pegarlo automaticamente en la aplicacion donde estabas trabajando.

## Funciones

- Historial persistente de textos, tablas e imagenes copiadas.
- Registros fijados para conservar contenido importante.
- Alias en registros fijados para identificarlos mas facil.
- Busqueda por contenido o alias.
- Pegado automatico en la aplicacion activa.
- Modo de pegado seleccionable:
  - Automatico.
  - Como tabla, util para rangos copiados desde Excel.
  - Sin formato.
  - Como imagen, cuando el portapapeles original incluia una imagen alternativa.
- Captura manual del portapapeles actual.
- Inicio automatico con macOS.
- Indicador de permiso de accesibilidad.

## Permisos de macOS

Para que el pegado automatico funcione, macOS debe permitir que la app controle el teclado mediante Accesibilidad.

Ruta:

```text
Ajustes del Sistema > Privacidad y seguridad > Accesibilidad
```

Activa `Copy&Paste` en la lista. Si el permiso no se refleja de inmediato, cierra y vuelve a abrir la app para que macOS actualice el estado.

## Persistencia

El historial se guarda localmente con SwiftData en:

```text
~/Library/Application Support/Copy&Paste/ClipboardHistory.store
```

El historial y los registros fijados se conservan despues de reiniciar la computadora.

## Desarrollo

Requisitos:

- macOS.
- Xcode.
- SwiftUI y SwiftData.

Abrir el proyecto:

```bash
open "Copy&Paste.xcodeproj"
```

Compilar desde terminal:

```bash
xcodebuild -project "Copy&Paste.xcodeproj" \
  -scheme "Copy&Paste" \
  -destination "platform=macOS" \
  -configuration Debug build
```

## Atajo principal

```text
Command + Shift + V
```

Este atajo muestra la ventana de historial. Al seleccionar un elemento se copia al portapapeles, se regresa a la aplicacion previa y se intenta pegar automaticamente.

## Notas

- Los rangos de Excel pueden incluir varias representaciones en el portapapeles. La app prioriza texto tabular para conservar filas y columnas, y guarda imagen alternativa cuando esta disponible.
- El pegado automatico depende del permiso de Accesibilidad y del comportamiento de la aplicacion destino.
