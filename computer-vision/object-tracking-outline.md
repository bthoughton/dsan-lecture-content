# DSAN 6500: Object Tracking — Combined Lecture Outline

### Course: Computer Vision
### Lecture: Object Tracking
### Prerequisite weeks: Object Detection I & II (Weeks 07–08)
### Duration: ~1.5–2 hours
### Style: Visual + Conceptual + Algorithmic (code demos + hand-drawn diagrams)

---

## Part 1: Motivation & Problem Framing (~10 min)

### What is object tracking?
- Detection answers "what is where?" in a **single frame**
- Tracking answers "which detection in frame $t$ is the **same object** in frame $t+1$?"
- Input: video frames → Output: object trajectories with consistent IDs
- "Detection is spatial. Tracking is spatiotemporal identity."

**Demo (Python):** Show a bounding box following a car across frames using OpenCV tracker

### Tracking vs Detection

| Task      | Output          | Scope       |
|-----------|-----------------|-------------|
| Detection | boxes per frame | single frame |
| Tracking  | consistent IDs  | across time  |

**Hand-drawn diagram:** Frame 1 has person A, B. Frame 2 has same persons but swapped positions. Highlight the identity swap problem.

### SOT vs MOT
- **Single Object Tracking (SOT)**: given a bounding box in frame 1, follow that one target
  - Use cases: surveillance zoom-in, sports player highlight, drone follow-mode
- **Multi-Object Tracking (MOT)**: detect and track **all** objects across every frame
  - Use cases: autonomous driving, crowd analysis, retail analytics
- This lecture focuses primarily on MOT (the harder, more general problem)

### Why tracking is hard
- Occlusion (objects disappear behind others or leave the frame)
- Appearance changes (lighting, pose, deformation)
- Camera motion (ego-motion vs object motion)
- Scale changes (objects approach or recede)
- Crowded scenes (many similar-looking objects close together)

---

## Part 2: Classical Tracking Foundations (~20 min)

### Optical flow
- Estimates per-pixel motion between consecutive frames
- **Brightness constancy assumption**: $I(x, y, t) = I(x + dx, y + dy, t + dt)$
- **Lucas-Kanade** (sparse, fast) vs **Farneback** (dense, slower)
- Useful as a motion cue, but not a full tracker by itself
- Limitations: fails under large displacements, occlusion, and illumination changes

**Demo (Python):** Farneback optical flow on synthetic moving rectangle → quiver plot of flow vectors

### Kalman filter (predict + correct)
- **State**: position, velocity (and optionally size, acceleration): $\mathbf{x} = [x, y, v_x, v_y]$
- **Predict step**: propagate the state forward using a motion model (constant velocity)
- **Update step**: correct the prediction when a new detection arrives
- Intuition: "where do I expect this object to be next frame, and how do I reconcile that with what I actually detect?"
- Handles noise and brief occlusions gracefully
- Limitations: assumes linear motion and Gaussian noise

**Hand-drawn diagram:** Prediction → Measurement → Correction loop

### Mean-shift / CAMShift
- Track object via color histogram distribution
- CAMShift adapts the window size to the target scale
- Fast and simple, but fragile under appearance changes and clutter

---

## Part 3: Tracking-by-Detection (~10 min)

### The modern paradigm
- Run a detector (Faster R-CNN, YOLO, etc.) on every frame independently
- Then **associate** detections across frames to form tracks
- Decouples "what is there?" from "who is who?"
- Why it dominates: leverages strong detectors, modular, scales to many objects

**Custom diagram:** `Frame → Detector → Boxes → Association → Tracks`

### The association problem
- Given $N$ detections in frame $t$ and $M$ tracks from frame $t-1$, find the best assignment
- This is a bipartite matching problem
- Matching cues: motion (position/velocity), appearance (embeddings), geometry (shape/size)

### Hungarian algorithm
- Solves the optimal assignment problem in polynomial time
- Input: cost matrix (e.g., $1 - \text{IoU}$ between each track–detection pair)
- Output: one-to-one assignment that minimizes total cost
- `scipy.optimize.linear_sum_assignment` does it in one line

**Demo (Python):** Build an IoU cost matrix, solve with scipy, visualize the assignment as a heatmap

---

## Part 4: SORT — Simple Online and Realtime Tracking (~10 min)

### Overview (Bewley et al., 2016)
- Surprisingly effective with just two ingredients: Kalman filter + Hungarian algorithm
- No appearance model — purely motion-based

### Pipeline
1. **Detect**: run detector on frame $t$ → get bounding boxes
2. **Predict**: propagate each existing track's Kalman state to frame $t$
3. **Associate**: compute IoU between predicted track boxes and new detections; solve with Hungarian algorithm
4. **Update**: matched tracks get a Kalman update; unmatched detections start new tracks; unmatched tracks are aged out after $T_{\text{lost}}$ frames

### Strengths and weaknesses
- **Strengths**: fast (~260 FPS), simple, good when objects move predictably
- **Weaknesses**: lots of ID switches when objects occlude or cross paths (no way to tell similar objects apart)

---

## Part 5: DeepSORT — Adding Appearance (~15 min)

### Motivation
- SORT fails when two people walk past each other — IoU-based association gets confused
- We need to tell objects **apart** beyond just position

### Re-ID embedding
- A small CNN trained for **re-identification**: given a crop, produce a feature embedding
- Objects with similar embeddings are likely the same identity
- Trained on re-ID datasets (e.g., Market-1501, CUHK03)

**Custom diagram:** Feature vectors clustering by identity in embedding space

### Association with motion + appearance
- Cost = weighted combination of:
  - **Mahalanobis distance** from the Kalman filter (motion gate)
  - **Cosine distance** between appearance embeddings
- $C = \lambda_1 \cdot d_{\text{motion}} + \lambda_2 \cdot d_{\text{appearance}}$
- Cascade matching: prioritize recently seen tracks over older ones

### DeepSORT pipeline
1. **Detect** → bounding boxes
2. **Extract appearance** → CNN embedding for each detection crop
3. **Predict** → Kalman predict for each track
4. **Associate** → cascaded matching using motion + appearance costs
5. **Update** → Kalman update for matched tracks

### DeepSORT vs SORT
- **Strengths**: dramatically fewer ID switches; handles occlusions better
- **Weaknesses**: slower (Re-ID adds overhead); appearance model needs training data; still struggles with very long occlusions

---

## Part 6: Siamese Trackers — Single-Object Tracking (~10 min)

### SiamFC (Bertinetto et al., 2016)
- **Core idea**: template matching via cross-correlation
- Extract a template from the target in frame 1
- In each subsequent frame, extract a larger search region
- Cross-correlate template features with search features → similarity heatmap
- Peak of the heatmap = predicted target location

**Academic diagram:** SiamFC architecture (twin CNN branches + cross-correlation)

### Strengths and limitations
- Fast and simple for single-object tracking
- No online model update in basic form → can drift on long sequences
- Modern extensions: SiamRPN (adds regression), SiamMask (adds segmentation)

---

## Part 7: Modern Directions (~10 min)

### ByteTrack (Zhang et al., 2022)
- Key insight: don't throw away low-confidence detections — they often correspond to occluded objects
- Two-stage association: first match high-confidence detections, then match remaining tracks to low-confidence detections
- State-of-the-art results with any detector, no appearance model needed
- Shows that better association strategy can matter more than a fancier model

### Joint detection and tracking
- Predict detections **and** track embeddings in one forward pass
- Examples: FairMOT, CenterTrack, JDE
- Advantage: faster, shared features
- Disadvantage: harder to train, detection–tracking tradeoff

### Transformer-based tracking
- **TrackFormer**, **MOTR**: transformer decoders where each "query" represents a track
- Object queries persist across frames — tracking = sequence modeling
- Attention mechanism naturally models interactions between objects
- Promising but computationally expensive

---

## Part 8: MOT Evaluation Metrics (~10 min)

### MOTA (Multiple Object Tracking Accuracy)
- $\text{MOTA} = 1 - \frac{\text{FN} + \text{FP} + \text{IDSW}}{\text{GT}}$
- Penalizes missed detections, false alarms, and identity switches
- Can be negative if errors exceed ground truth count
- Dominated by detection quality

### MOTP (Multiple Object Tracking Precision)
- Average IoU between matched tracks and ground truth
- Measures localization quality, not association quality

### IDF1
- Harmonic mean of identification precision and recall
- Better at capturing **identity consistency** than MOTA

### ID switches
- Number of times a track's identity changes mid-sequence
- Directly measures association failure

### Comparison table

| Metric | Measures | Sensitive to |
|--------|----------|-------------|
| MOTA   | Overall accuracy | Detection quality + ID switches |
| MOTP   | Localization | Bounding box precision |
| IDF1   | Identity consistency | Association quality |
| IDSW   | Re-ID failures | Occlusion + crowding |

**Custom diagram:** Ground truth vs predicted tracks side-by-side

---

## Part 9: Failure Modes (~5 min)

### Common tracking failures
- **Occlusion**: object temporarily disappears → tracker loses it or assigns wrong ID on return
- **Re-identification failure**: after occlusion, tracker assigns a new ID to the same object
- **Drift**: tracker gradually slides off the target over time (especially SOT)
- **ID switches in crowds**: similar-looking objects in close proximity swap identities

**Visual:** Show video or frame sequence where tracker fails, annotate the failure type

---

## Part 10: Practical Considerations (~5 min)

### Choosing a tracker
- **Few objects, predictable motion** → SORT is fine
- **Crowded scenes, frequent occlusion** → DeepSORT or ByteTrack
- **Need real-time on edge device** → SORT or ByteTrack (no Re-ID overhead)
- **Research / best accuracy** → Transformer-based methods

### Common pitfalls
- Tracking quality is bottlenecked by detection quality — improve the detector first
- Frame rate matters: at low FPS, objects move more between frames → association is harder
- Camera motion can be handled with background subtraction or ego-motion compensation
- Re-ID models don't generalize well across domains

### Connection to course projects
- Tracking is listed as an **advanced extension** for Check-In 3
- Natural fit if your project involves video data (surveillance, sports, traffic, etc.)
- Build tracking on top of your Week 8 detection baseline

---

## Key Takeaways (Summary Slide)

1. Tracking = detection + **data association** across time
2. The Kalman filter provides a **motion prior** (predict where, correct when you see)
3. The Hungarian algorithm solves **optimal assignment** between tracks and detections
4. SORT = Kalman + Hungarian (fast, simple, fragile on occlusion)
5. DeepSORT adds **appearance embeddings** to reduce ID switches
6. Siamese trackers (SiamFC) handle **single-object tracking** via template matching
7. ByteTrack shows that **keeping low-confidence detections** is a powerful trick
8. Evaluation: MOTA captures overall quality; IDF1 captures identity consistency
9. In practice, **detection quality is the bottleneck** — improve the detector before tuning the tracker

---

## Demos & Code Cells

1. **Optical flow visualization**: Farneback on synthetic moving rectangle → quiver plot
2. **Hungarian algorithm**: IoU cost matrix → scipy assignment → heatmap visualization
3. **Car tracking demo**: OpenCV KCF tracker on synthetic video → bounding box + trajectory

---

## Visual Asset Plan

### Python visuals (live or pre-recorded)
- Optical flow field (quiver plot)
- Cost matrix heatmap with assignment overlay
- Real-time bounding box tracking with trajectory

### Academic diagrams (from papers)
- SiamFC architecture
- DeepSORT pipeline
- TrackFormer / transformer tracking

### Hand-drawn diagrams (critical for intuition)
1. Identity switching problem (two people crossing paths)
2. Tracking-by-detection pipeline
3. Kalman predict-correct loop
4. Siamese matching (template vs search region)
5. Occlusion failure → re-ID failure

---

## References

- Bewley, A., Ge, Z., Ott, L., Ramos, F., & Upcroft, B. (2016). *Simple Online and Realtime Tracking*. ICIP 2016.
- Bertinetto, L., Valmadre, J., Henriques, J. F., Vedaldi, A., & Torr, P. H. S. (2016). *Fully-Convolutional Siamese Networks for Object Tracking*. ECCV 2016 Workshops.
- Wojke, N., Bewley, A., & Paulus, D. (2017). *Simple Online and Realtime Tracking with a Deep Association Metric*. ICIP 2017.
- Zhang, Y., Sun, P., Jiang, Y., et al. (2022). *ByteTrack: Multi-Object Tracking by Associating Every Detection Box*. ECCV 2022.
- Meinhardt, T., Kirillov, A., Leal-Taixe, L., & Feichtenhofer, C. (2022). *TrackFormer: Multi-Object Tracking with Transformers*. CVPR 2022.
- Bernardin, K. & Stiefelhagen, R. (2008). *Evaluating Multiple Object Tracking Performance: The CLEAR MOT Metrics*. JIVP.
