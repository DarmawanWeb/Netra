# Operator guide (Indonesian)

`../NETRA-Panduan-Operator.pdf` is the guide for the people who run the patrols every day: operators,
security staff and supervisors, without a technical background. It covers safety and the e-stop, the
daily start with the Genisom L1W and the handheld, the NETRA dashboard, patrols, anomaly validation,
schedules, routes (and recording them), reports, crowd, troubleshooting, and a one-page card.

| File | |
|---|---|
| `main.tex` | the text, in Indonesian |
| `preamble.tex` | page style, colours (the dashboard palette), boxes, screenshot frame |
| `img/` | dashboard screenshots (Indonesian, light theme) of a simulated L1W on the local stack |

Build with TeX Live (`latexmk`, TikZ, tcolorbox, tocloft, psnfss fonts):

```bash
make          # builds main.pdf and copies it to ../NETRA-Panduan-Operator.pdf
make clean
```

When the dashboard changes, retake the affected screenshots at 1440 x 900 (device scale 2, Indonesian,
light theme) and keep the file names.
