<div align="center">

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README_TR.md">Türkçe</a> ·
  <a href="README_JA.md">日本語</a> ·
  <a href="README_ZH.md">简体中文</a> ·
  <strong>Español</strong>
</p>

<img src="assets/icon.png" width="128" height="128" alt="Icono de EXdl">

# EXdl
### Gestor de instalación y almacenamiento en discos externos para macOS

**Instala aplicaciones de Mac directamente en tu disco externo conservando la compatibilidad con Launchpad y Spotlight.**

<br>

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111?style=flat-square&logo=apple&logoColor=white)](#requisitos-del-sistema)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-0A84FF?style=flat-square)](#requisitos-del-sistema)
[![Versión](https://img.shields.io/badge/Versi%C3%B3n-v1.1.0-blue?style=flat-square)](https://github.com/erdembeler/exdl/releases/latest)
[![Notarized](https://img.shields.io/badge/Apple-notarized-34C759?style=flat-square)](#instalación)
[![Swift 5.10](https://img.shields.io/badge/Swift-5.10-F05138?style=flat-square&logo=swift&logoColor=white)](Package.swift)
[![Licencia MIT](https://img.shields.io/badge/Licencia-MIT-yellow?style=flat-square)](LICENSE)

[**Descargar última versión**](https://github.com/erdembeler/exdl/releases/latest) &nbsp;·&nbsp; [Cómo funciona](#cómo-funciona) &nbsp;·&nbsp; [Permisos](#permisos-y-motivos) &nbsp;·&nbsp; [Compilación desde código fuente](#compilación-desde-código-fuente)

</div>

<br>

EXdl es una aplicación nativa y ligera para la barra de menús de macOS diseñada para convertir tu SSD externo en el destino principal de tus aplicaciones sin perder la integración con el sistema.

---

## El problema

El almacenamiento SSD interno de los ordenadores Mac no se puede ampliar tras la compra. Las aplicaciones pesadas (entornos de desarrollo, software 3D, motores gráficos y juegos) llenan rápidamente el almacenamiento interno.

Al descargar una aplicación mediante un archivo `.dmg`, la ventana de instalación de macOS solo permite arrastrar hacia la carpeta `/Applications` del disco interno. Si mueves manualmente la aplicación a un disco externo y creas un alias o enlace simbólico (symlink):
- Launchpad, Spotlight y la vista de Aplicaciones de macOS Sequoia a menudo no indexan los enlaces simbólicos, por lo que la aplicación no aparece en las búsquedas.
- Al hacer clic en el enlace sin el disco externo conectado, la aplicación falla de forma silenciosa o muestra errores confusos.
- Cuando la aplicación se actualiza automáticamente, el actualizador sobrescribe el enlace simbólico y descarga una copia completa en el SSD interno, volviendo a agotar el espacio sin que te des cuenta.

---

## Cómo funciona

<p align="center">
  <img src="assets/how-it-works.svg" width="720" alt="Flujo de trabajo de instalación y lanzador inteligente de EXdl">
</p>

EXdl no depende de enlaces simbólicos frágiles. Utiliza una arquitectura de **Lanzador Inteligente (Smart App Stub)**:
1. Al abrir una imagen de disco (`.dmg`), EXdl la detecta automáticamente y muestra una ventana nativa de instalación hacia tu SSD externo.
2. El paquete completo de la aplicación se aloja de forma segura en tu disco externo.
3. En la carpeta `/Applications` interna, EXdl crea un lanzador nativo ultraligero (~500 KB) que conserva el icono original, los metadatos y el identificador de la aplicación.
4. Launchpad, Spotlight y el Dock lo reconocen como una aplicación legítima instalada.
5. Si abres la aplicación con el disco desconectado, EXdl te muestra un aviso claro pidiéndote conectar el disco, en lugar de bloquearse o cerrarse de improviso.

---

## Características principales

- **Detección automática de imágenes de disco** — Captura archivos `.dmg` al abrirse, permite la instalación directa en el disco externo y desmonta la imagen al finalizar.
- **Protección contra actualizaciones** — Si una actualización sobrescribe el lanzador en el disco interno, EXdl lo detecta y restaura la nueva versión automáticamente a tu disco externo.
- **Panel de control y migración** — Supervisa el almacenamiento interno y externo en un solo lugar. Migra aplicaciones existentes del disco interno al externo con un solo clic, o restáuralas cuando quieras.
- **Protección de aplicaciones incompatibles** — Detecta y evita mover aplicaciones que requieren residir obligatoriamente en el disco de arranque (como Xcode, herramientas de desarrollo de Apple, utilidades con extensiones de sistema de macOS o demonios de inicio en segundo plano).
- **10 iconos personalizables para la barra de menús** — Elige entre 10 diseños vectoriales Retina en Ajustes (icono por defecto: Monograma EX). Se muestra con relleno sólido cuando la monitorización está activa y con contorno lineal al pausarse.
- **Actualizaciones de software OTA integradas** — Comprueba nuevas versiones desde GitHub Releases, verifica la firma oficial de Apple Developer ID y actualiza la aplicación sin descargas manuales.
- **Ligero y privado** — Funciona en silencio en la barra de menús, consume mínimos recursos y no realiza conexiones a internet más allá de la comprobación voluntaria de actualizaciones.

---

## Tabla comparativa

| Característica | macOS estándar | Enlaces simbólicos manuales | Con EXdl |
| :-- | :-- | :-- | :-- |
| **Destino de instalación DMG** | Solo disco interno | Requiere copia manual | Instalación directa en disco externo |
| **Launchpad y Spotlight** | Compatible | Frecuentemente no indexado | Totalmente compatible |
| **Disco desconectado** | No aplica | Cierre silencioso / error | Aviso claro para reconectar el disco |
| **Actualizaciones de apps** | Escribe en disco interno | Destruye el enlace | Se migra automáticamente al disco externo |
| **Ahorro de espacio interno** | 0 GB | Alto pero inestable | Ahorro completo, fiable y nativo |

---

## Permisos y motivos

macOS requiere los siguientes permisos de privacidad para el correcto funcionamiento de EXdl:

1. **Gestión de aplicaciones (`App Management`) — Obligatorio**
   - **Por qué se necesita:** EXdl requiere autorización para crear los lanzadores en `/Applications` y mover paquetes de aplicaciones a tu disco externo.
   - **Cómo activarlo:** Ve a *Ajustes del Sistema → Privacidad y seguridad → Gestión de aplicaciones* y activa EXdl. Si no aparece en la lista, pulsa el botón `+` y añade `/Applications/EXdl.app`.
2. **Acceso total al disco (`Full Disk Access`) — Recomendado**
   - **Por qué se necesita:** Permite leer imágenes de disco en Descargas y escribir en unidades externas sin que macOS muestre solicitudes repetitivas para cada carpeta.
   - **Cómo activarlo:** Ve a *Ajustes del Sistema → Privacidad y seguridad → Acceso total al disco* y activa EXdl.

---

## Instalación

1. Descarga la versión más reciente desde la página de [GitHub Releases](https://github.com/erdembeler/exdl/releases/latest) (`EXdl-1.1.0.dmg` o `EXdl-1.1.0.zip`).
2. Abre la imagen de disco y arrastra **EXdl** a la carpeta **Applications**.
3. Inicia EXdl. El asistente inicial te guiará en la selección del idioma, el disco externo de destino y la concesión de permisos.
4. Tras completar el asistente, EXdl permanecerá activo en la barra superior de menús.

Todos los ejecutables están firmados con un certificado oficial Apple Developer ID y han sido notarizados por Apple.

---

## Requisitos del sistema

- macOS 14 Sonoma o posterior
- Ordenador Mac con Apple Silicon (M1 / M2 / M3 / M4)
- Disco externo formateado en **APFS** (recomendado) o **Mac OS Plus (con registro)**

---

## Compilación desde código fuente

```bash
git clone https://github.com/erdembeler/exdl.git
cd exdl

# Compilar la aplicación
./build_app.sh

# Empaquetar distribución DMG y ZIP
./package_release.sh
```

---

## Licencia

Este proyecto está bajo la [Licencia MIT](LICENSE).
