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

## Exportar la app

En macOS el "ejecutable" que normalmente se comparte no es el binario suelto, sino el paquete `.app`. Dentro de ese paquete esta el binario real en:

```text
Copy&Paste.app/Contents/MacOS/Copy&Paste
```

Para uso local, puedes generar una version Release desde Xcode:

1. Abre `Copy&Paste.xcodeproj`.
2. Selecciona el scheme `Copy&Paste`.
3. Cambia la configuracion a `Release` si lo necesitas.
4. Usa `Product > Archive`.
5. En Organizer, elige `Distribute App`.
6. Para uso personal o pruebas, exporta/copia la `.app`.
7. Copia `Copy&Paste.app` a `/Applications`.

Tambien puedes generar una `.app` desde terminal:

```bash
rm -rf build dist

xcodebuild -project "Copy&Paste.xcodeproj" \
  -scheme "Copy&Paste" \
  -destination "platform=macOS" \
  -configuration Release \
  -derivedDataPath "build/DerivedData" \
  build

mkdir -p dist
ditto "build/DerivedData/Build/Products/Release/Copy&Paste.app" "dist/Copy&Paste.app"
ditto -c -k --keepParent "dist/Copy&Paste.app" "dist/Copy&Paste.zip"
```

El archivo para compartir quedara en:

```text
dist/Copy&Paste.zip
```

Si quieres distribuirla fuera de tu Mac, considera firmar y notarizar la app con una cuenta de Apple Developer. Si no esta firmada/notarizada, macOS puede mostrar una advertencia de seguridad al abrirla en otra computadora.

## Atajo principal

```text
Command + Shift + V
```

Este atajo muestra la ventana de historial. Al seleccionar un elemento se copia al portapapeles, se regresa a la aplicacion previa y se intenta pegar automaticamente.

## Notas

- Los rangos de Excel pueden incluir varias representaciones en el portapapeles. La app prioriza texto tabular para conservar filas y columnas, y guarda imagen alternativa cuando esta disponible.
- El pegado automatico depende del permiso de Accesibilidad y del comportamiento de la aplicacion destino.
