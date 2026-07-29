# ArchSpiral

ArchSpiral is an iPad application that digitizes the International Cooperative Ataxia Rating Scale (ICARS) Archimedean spiral assessment. Developed for use with either Apple Pencil or finger touch input, the application preserves conventional ICARS spiral scoring while automatically generating objective quantitative digital biomarkers of motor performance for clinical research and longitudinal disease monitoring.

## Overview

ArchSpiral enables participants to complete the standardized ICARS Archimedean spiral tracing task on an iPad while capturing high-resolution digital drawing data. In addition to providing an automated ICARS-compatible spiral morphology score, the application extracts quantitative measures of tracing performance that enhance the assessment of motor function during ICARS evaluations and facilitate longitudinal disease monitoring.

Originally developed for rare disease natural history studies, ArchSpiral provides a portable, standardized platform for objective motor assessment in both clinical and research settings.

## Features

- Apple Pencil or finger touch–based spiral tracing
- Standardized three-turn Archimedean spiral template
- Automated ICARS-compatible spiral morphology score (0–4)
- Real-time digital drawing capture
- Objective quantitative motor performance metrics
- Exportable results (structured report, PNG image, and native drawing file)
- Native iPad application written in Swift, SwiftUI, and PencilKit

## Quantitative Metrics

ArchSpiral automatically computes:

- Automated ICARS-compatible spiral morphology score (0–4)
- Tracing accuracy
- Root mean squared error (RMSE)
- Drawing duration
- Average drawing speed
- Pen/finger lift count
- Pause count
- Steadiness score

## Research Applications

ArchSpiral was developed for standardized digital motor assessment in:

- Congenital disorders of glycosylation (CDG)
- Cerebellar ataxias
- Rare neurologic disorders
- Natural history studies
- Clinical trials
- Remote and longitudinal patient monitoring

## Requirements

- iPad
- iPadOS 18 or later
- Apple Pencil (optional; finger touch is also supported)
- Xcode 16 or later (for development)

## Installation

Clone the repository:

```bash
git clone https://github.com/DanielSchecter/ArchSpiral.git
```

Open `ArchSpiral.xcodeproj` in Xcode.

Build and run the application on a compatible iPad.

## Citation

If you use ArchSpiral in your research, please cite the associated publication once available. Citation information and DOI will be added following publication.

## Contact

**Daniel R. Schecter, MD, MS**  
Department of Genetics and Genomic Sciences  
Icahn School of Medicine at Mount Sinai  

📧 Daniel.Schecter@mountsinai.org
