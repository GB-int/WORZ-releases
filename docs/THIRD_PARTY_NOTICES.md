# Уведомления о сторонних компонентах WORZ

Обновлено: 2026-09-28 17:47:33 +03:00 — переводчик страниц TWP включён в общую сборку с SYGI и настройками агентов; убрана устаревающая привязка уведомлений к версии приложения.

Translate Web Pages 10.2.1.0 (FilipePS и участники проекта), MPL-2.0: движок перевода текста страниц. Исходники, полный текст лицензии, происхождение пакета и описание адаптации WORZ поставляются в `resources/extensions/page-translation/` внутри `app.asar.unpacked`. Источник: https://github.com/FilipePS/Traduzir-paginas-web/releases/tag/v10.2.1.0. Проприетарные условия WORZ не ограничивают права на этот компонент по MPL-2.0.

Обновлено: 2026-09-07 10:03:11 +03:00.

Этот документ относится к production Electron-контуру WORZ. Полные тексты лицензий имеют приоритет над кратким перечнем ниже. Полный machine-readable SBOM в формате CycloneDX прикладывается к каждому GitHub Release.

Проприетарная лицензия WORZ не заменяет и не ограничивает лицензии сторонних компонентов. В свою очередь, лицензии сторонних компонентов не предоставляют прав на проприетарный код, материалы и сборку WORZ. Актуализировано: 2026-08-21 19:00:37 +03:00.

## Компоненты production package

| Компонент | Версия | Лицензия | Использование |
|---|---:|---|---|
| Electron | 43.5.0 | MIT | Desktop host, Chromium renderer, Node.js main process. Обновлено: 2026-09-08 09:52:00 +03:00. |
| Chromium и его third-party зависимости | версия из Electron 43.3.0 | набор open-source лицензий | Browser engine; полный перечень поставляется в `LICENSES.chromium.html`. |
| Node.js | версия из Electron 43.3.0 | MIT и лицензии зависимостей | Main/preload runtime внутри Electron. |
| Lucide | 1.28.0 | ISC | UI-иконки WORZ. |
| yauzl | 2.10.0 | MIT | Безопасное чтение и проверка ZIP/CRX payload расширений. |
| buffer-crc32 | 0.2.13 | MIT | Проверка CRC32 внутри ZIP/CRX-контура `yauzl`. |
| fd-slicer | 1.1.0 | MIT | Ограниченное чтение диапазонов файлов внутри `yauzl`. |
| pend | 1.2.0 | MIT | Координация асинхронного чтения внутри `fd-slicer`. |
| Voice Over Translation, `ilyhalight/voice-over-translation` | 1.11.8, commit `6ebccdef7614297dd49b8d7ef6806fbf96ef4035` | MIT | Закреплённое расширение перевода видео; текст его лицензии включён в официальную сборку. |
| AMD FidelityFX FSR 1 и GLSL-порт SharpView | FSR 1, [коммит порта](https://github.com/skateddu/sharpview-fsr-video-upscaler/tree/e5e7b56755d123c076ce1c6eb0605721f0027c48/src/core/shaders) | MIT | Адаптированные шейдеры EASU и RCAS для видеоокна WORZ. Актуализировано 2026-11-25 09:59 +03:00. |

### Шейдеры Anime4K

Актуализировано 2026-11-26. WORZ использует шейдеры Restore CNN M, Restore CNN Soft M и Upscale CNN x2 M из [Anime4K v4.0.1](https://github.com/bloc97/Anime4K/releases/tag/v4.0.1). Они выполняются через WebGL2 в отдельном окне. Уведомление MIT и авторские права bloc97 (2019–2021) сохранены перед каждым шейдером.

### Real-ESRGAN и NVIDIA TensorRT RTX

Актуализировано 2026-11-27 21:01 +03:00. Веса Real-ESRGAN AnimeVideo v3 поставляются с уведомлением BSD-3-Clause в `browser-video-window/LICENSE.Real-ESRGAN.txt`. В Windows x64 сборках с режимом TensorRT RTX используется подписанная NVIDIA библиотека `tensorrt_rtx_1_7.dll` версии 1.7.1.116. Библиотека используется видеоворкером WORZ. [Лицензия NVIDIA TensorRT RTX](https://docs.nvidia.com/deeplearning/tensorrt-rtx/latest/reference/sla.html).

### Лицензия шейдеров FSR 1 и порта SharpView

Добавлено 2026-11-25 09:59 +03:00.

Copyright (c) 2026 Andrea Cadeddu

Copyright (c) 2021 Advanced Micro Devices, Inc. All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

### Уведомления в сборке

Установленная Electron-сборка содержит собственные уведомления Electron `LICENSE` и `LICENSES.chromium.html`. Внутри `app.asar` файл `BUNDLED_DEPENDENCY_LICENSES.txt` формируется из esbuild metafile и содержит полный локальный текст лицензии каждого npm-пакета, попавшего в minified runtime bundle, а также Lucide. Сборка завершается ошибкой, если у найденного пакета нет версии, типа лицензии или локального `LICENSE*`. Путь `resources/extensions/vot/src/extension` является закреплённым compiled third-party payload VOT и разрешён только внутри этой точной границы; это не исходное дерево WORZ. Пользовательская лицензия WORZ устанавливается как `WORZ-LICENSE.txt` и публикуется как `LICENSE` рядом с release assets. Provenance и контрольные суммы закреплённого VOT artifact хранятся Правообладателем и сверяются при подготовке официальной сборки. Актуализировано: 2026-09-01 21:06:30 +03:00.

## Инструменты сборки

| Компонент | Версия | Лицензия | Роль |
|---|---:|---|---|
| `@electron/packager` | 20.3.0 | BSD-2-Clause | Формирование Windows x64 package; обновлено для устранения high-risk уязвимости legacy extractor. Актуализировано: 2026-08-21 18:07:00 +03:00. |
| esbuild | 0.28.2 | MIT | Сборка renderer frontend и minified Electron runtime bundles без source maps. Актуализировано: 2026-09-01 21:00:38 +03:00. |
| Inno Setup | 6.7.1 | лицензия Inno Setup | Формирование `WORZ-Setup.exe`; compiler не встраивается в приложение. |

## Брендовые материалы

Логотипы WORZ — официальные материалы проекта; их provenance и контрольные суммы хранятся Правообладателем.

Иконки сторонних сервисов используются только для идентификации соответствующих сервисов. Их источники и контрольные суммы хранятся Правообладателем. Торговые марки принадлежат их правообладателям; присутствие иконки не означает партнёрство или одобрение WORZ. Актуализировано: 2026-08-21 19:38:00 +03:00.
