# Machine Learning Pipeline Reference (v3.0)

| Field | Value |
| :--- | :--- |
| **Document Type** | Comprehensive ML Engineering & Pipeline Reference |
| **Status** | Canonical Reference |
| **Owner** | AI Agent & Human Practitioner |
| **Scope** | Global Deep Learning Methodology |
| **Created** | 2026-07-24T09:00:00+07:00 |
| **Last Updated** | 2026-09-06T21:05:00+07:00 |
| **Reference** | [docs/README.md](../README.md), [agents/rules/PYTORCH_FRAMEWORK_RULES.md](../../agents/rules/PYTORCH_FRAMEWORK_RULES.md) |

---

# ML Pipeline Reference

**Version:** 2.0
**Scope:** Steps 1–18 (Problem Framing → Experimental Methodology), plus introductory coverage of Error Analysis and Interpretability. See coverage table below for what remains thin.
**Audience:** Human practitioners and AI coding agents.
**How to use:** Follow this document top-to-bottom before writing a single line of training code. Every section states *what*, *why*, and *when not to* — read all three.

---

## ⚠️ Coverage Status

Most of the pipeline is now documented. A few subtopics were mentioned in class but not explained in enough depth to act on confidently — treat these as **known gaps**, not silent defaults:

| Topic                                                                                | Status                                                                                                                                   |
| ------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Statistical significance testing (p-values, t-test, bootstrap, confidence intervals) | Mentioned, not detailed in class. §17.4 gives a minimal, conservative treatment — verify against course material before relying on it. |
| Error Analysis (root-cause analysis by failure subgroup)                             | Mentioned only as a pipeline stage name. §19 gives a standard framework, not lecture content.                                           |
| Model Interpretability — Global vs. Local                                           | Mentioned, definitions not given in class. §20 gives standard definitions — verify terminology against course material.                |
| Hyperparameter tuning — learning rate effects                                       | Instructor's note was incomplete ("failed to noted"). §15.3 fills this from general ML theory.                                          |

Where this document fills a gap with general ML knowledge rather than your lecture notes, it is marked **[inference — verify in class]**.

---

## Full Pipeline at a Glance

```
1.  Identify the ML paradigm
         ↓
2.  Understand the three pillars
         ↓
3.  Geometric survey of the data (EDA)
         ↓
4.  Handle missing values
         ↓
5.  Detect & treat outliers
         ↓
6.  Feature scaling
         ↓
7.  Encode categorical variables
         ↓
8.  Handle class imbalance
         ↓
9.  Feature engineering (construction, encoding, PCA, transforms)
         ↓
10. Train / test split  ← BEFORE any statistic is computed (leakage boundary)
         ↓
11. Baseline model
         ↓
12. Model selection (No Free Lunch — match inductive bias to data geometry)
         ↓
13. Bias–variance analysis
         ↓
14. Hyperparameter tuning
         ↓
15. Train model
         ↓
16. Evaluation metrics
         ↓
17. Cross-validation (K-Fold)
         ↓
18. Scientific experimentation (single-variable principle)
         ↓
19. Statistical validation (significance, confidence intervals)
         ↓
20. Error analysis
         ↓
21. Model interpretability
```

> **Critical ordering note:** Step 10 (train/test split) must happen *before* steps 4–9 compute any statistic (mean, std, min/max, target-encoding maps, etc.) are fit. The diagram above shows the conceptual pipeline; in implementation, steps 4–9's *fitting* happens only on the train partition. See §10 for why this matters — it is the single most common bug in student ML code.

> **Rule #0 — Never start from the algorithm.**
> Start from the data. Wrong assumptions at step 3 corrupt every later step. A mediocre algorithm on well-prepared data beats a fancy algorithm on raw data.

---

## 1. ML Mind Map — Identify the Problem Type

The very first question is not *"which model do I use?"*

The first question is:

```
Does the data have labels?
    YES → Supervised Learning
    NO  → Does a reward signal exist?
              YES → Reinforcement Learning
              NO  → Unsupervised Learning
```

Choosing the wrong paradigm invalidates every downstream decision. Lock this in before touching the data.

---

## 2. Three Pillars of ML

### 2.1 Supervised Learning

- Data: `(X, y)` pairs — inputs with known labels.
- Goal: Learn `f: X → y` that generalizes to unseen samples.
- Tasks: Classification, Regression.
- Typical algorithms: Linear/Logistic Regression, Decision Tree, Random Forest, SVM, MLP (Neural Network), Gradient Boosting.

#### ⚠️ Pitfall — Label Quality in the Real World

Public datasets (Kaggle, Hugging Face, UCI) come pre-labeled. Real industry data does **not**.

```
Raw unlabeled data
    ↓
Manual labeling by human judgment
    ↓
Subjective / inconsistent labels
    ↓
Model learns human bias, not ground truth
    ↓
Biased predictions in production
```

**Consequence:** Label quality is the hard ceiling on supervised model performance. No algorithm can fix corrupted labels.

---

### 2.2 Unsupervised Learning

- Data: `X` only — no labels.
- Goal: Discover hidden structure.
- Tasks: Clustering, Dimensionality Reduction, Density Estimation, Anomaly Detection.
- Typical algorithms: K-Means, GMM (Gaussian Mixture Model), PCA, DBSCAN, t-SNE, UMAP.

---

### 2.3 Reinforcement Learning

- Setup: Agent ↔ Environment loop.

```
Observe state s_t
    ↓
Select action a_t (policy)
    ↓
Receive reward r_t
    ↓
Transition to state s_{t+1}
    ↓
Update policy
```

- Goal: Maximize cumulative discounted reward `Σ γ^t r_t`.

---

## 3. Geometric Survey of the Data (EDA)

> Think of every sample as a point in an N-dimensional space. Before preprocessing, understand the **shape** of that space.

**Why this matters:** Preprocessing decisions (scaling method, imputation strategy, encoding) are determined by data geometry — not by defaults.

### ⚠️ Pitfall — Skipping EDA

```
Raw data
    ↓  (no exploration)
Wrong assumptions
    ↓
Wrong preprocessing
    ↓
Wrong algorithm choice
    ↓
Poor performance with no clear diagnosis
```

---

### 3.1 Lens 1 — Global Overview

Questions to answer before anything else:

| Question                                                           | Tool                         |
| ------------------------------------------------------------------ | ---------------------------- |
| How many samples? How many features?                               | `df.shape`                 |
| What are the feature types? (numeric, categorical, bool, datetime) | `df.dtypes`, `df.info()` |
| Are there missing values?                                          | `df.isnull().sum()`        |
| What are the value ranges?                                         | `df.describe()`            |
| Any obvious anomalies or impossible values?                        | visual inspection            |

---

### 3.2 Lens 2 — Univariate Distribution

Examine each feature independently. Every feature has its own probability distribution.

Tools:

- Histogram / KDE plot — detect skew, multimodality, gaps.
- Box plot — visualize spread and outliers.
- Summary statistics: mean, median, std, skewness, kurtosis.

**What to determine per feature:**

```
Is the distribution roughly symmetric (Gaussian)?
    YES → mean is representative; standardization safe
    NO  → distribution is skewed; use median; consider log transform
```

---

### 3.3 Lens 3 — Multivariate Relationships

Study interactions between features.

Tools:

- Correlation matrix (heatmap).
- Scatter matrix / pair plot.
- Mutual information.

**Correlation interpretation:**

| `r` value  | Meaning                       | Suggested Action                                     |
| ------------ | ----------------------------- | ---------------------------------------------------- |
| `r ≈ ±1` | Strong co-linear relationship | Consider removing one, or combine                    |
| `0.3 <       | r                             | < 0.7`                                               |
| `r ≈ 0`   | Independent                   | Keep both; check non-linear relationships separately |

> **Warning:** Correlation only captures linear relationships. Two features can have `r = 0` but strong non-linear dependence. Always supplement with scatter plots.

> **Warning:** Never remove a feature based on correlation alone. Consult domain knowledge and observed model behavior first.

---

### 3.4 Why Distribution Knowledge Drives Everything

Distribution is the input to every downstream decision:

| Decision                        | Requires Distribution Knowledge                    |
| ------------------------------- | -------------------------------------------------- |
| Missing value imputation method | Yes — mean vs median vs KNN                       |
| Outlier detection threshold     | Yes — IQR bounds depend on spread                 |
| Scaling method                  | Yes — Gaussian → standardize; bounded → min-max |
| Feature engineering targets     | Yes — skewed features benefit from log transform  |
| Model family selection          | Yes — linear vs non-linear separability           |

---

## 4. Missing Values

> Handle missing values before any model training. The correct strategy depends on the data type and the distribution.

---

### 4.1 Numerical Features

#### Distribution is approximately Gaussian (symmetric)

```python
from sklearn.impute import SimpleImputer
imputer = SimpleImputer(strategy='mean')
```

**Why:** Mean is the maximum-likelihood estimate for a Gaussian distribution.

#### Distribution is skewed or has outliers

```python
imputer = SimpleImputer(strategy='median')
```

**Why:** Median is robust to extreme values. Mean is pulled toward outliers and destroys the true distribution center.

**Concrete example:**

```
Salary values: [20k, 22k, 25k, 28k, 5000k]
Mean ≈ 1019k  ← severely distorted
Median = 25k  ← representative
```

Filling a missing salary with `1019k` is incorrect and corrupts the feature distribution for every downstream step.

#### Multivariate missing pattern (missingness related to other features)

```python
from sklearn.impute import KNNImputer
imputer = KNNImputer(n_neighbors=5)
```

**Why:** KNN uses the local neighborhood in feature space to estimate the missing value, preserving local structure better than any global statistic.

---

### 4.2 Categorical Features

Mean and median are undefined for categorical variables. Options:

| Strategy                               | When to Use                                       |
| -------------------------------------- | ------------------------------------------------- |
| **Mode** (`most_frequent`)     | Distribution is clearly dominated by one category |
| **New category `"Unknown"`**   | Missingness itself may be informative             |
| **Domain-specific fill**         | Business rules dictate the correct value          |
| **KNN Imputer** (after encoding) | Missingness correlates with other features        |

> **AI Agent Note:** Never apply `strategy='mean'` to a categorical column. Always check `dtype` first.

---

### 4.3 Decision Tree for Imputation Strategy

```
Feature is numerical?
    YES → Distribution is Gaussian?
              YES → Mean imputation
              NO  → Median imputation
          Missingness correlates with other features?
              YES → KNN Imputer (overrides mean/median)
    NO  (categorical) →
          Missingness itself is informative?
              YES → Add "Unknown" category
              NO  → Mode imputation or domain fill
```

---

## 5. Outlier Detection and Treatment

An **outlier** is a sample that deviates significantly from the expected distribution.

**Outliers may be:**

- Data entry or sensor errors → should be corrected or removed.
- Genuine rare events → **must be kept** (fraud, disease, faults are precisely the minority events a model needs to learn).

> **Rule:** Never blindly remove outliers. First determine: is this an error, or is this signal?

---

### 5.1 Why Outliers Break ML

#### They hijack the loss function

Linear Regression (OLS) minimizes `Σ (y_i - ŷ_i)²`. Squaring the error means one extreme point contributes an enormous loss:

```
Normal points: 5 points with error ≈ 1  →  loss += 5
Outlier:       1 point  with error = 50 →  loss += 2500
```

The optimizer pulls the entire model toward one outlier. The fitted line no longer represents the bulk of the data.

#### They corrupt scaling

Min-Max scaling is defined as:

```
x' = (x - x_min) / (x_max - x_min)
```

One outlier extends `x_max` or `x_min` dramatically, compressing all normal values into a tiny range near 0 or 1. The feature effectively loses information.

#### They distort imputation

If a feature has outliers and you use mean imputation for missing values, the imputed values will reflect the outlier rather than the true distribution center. This is the reason the distribution check in Step 4 must come **before** imputation.

---

### 5.2 Detection Methods

#### Box Plot (visual, fast)

```
|----[Q1----median----Q3----|    ●
           IQR                outlier
```

Use during EDA for quick visual identification.

#### IQR Rule (numerical)

```
Q1  = 25th percentile
Q3  = 75th percentile
IQR = Q3 - Q1

Lower bound = Q1 - 1.5 × IQR
Upper bound = Q3 + 1.5 × IQR
```

Points outside `[Lower, Upper]` are flagged as potential outliers.

```python
Q1 = df[col].quantile(0.25)
Q3 = df[col].quantile(0.75)
IQR = Q3 - Q1
lower = Q1 - 1.5 * IQR
upper = Q3 + 1.5 * IQR
outliers = df[(df[col] < lower) | (df[col] > upper)]
```

#### Other Methods (beyond current course scope)

| Method                     | Characteristic                                 |
| -------------------------- | ---------------------------------------------- |
| Z-score                    | Assumes Gaussian; flags points > 3σ from mean |
| Isolation Forest           | Tree-based; works in high dimensions           |
| Local Outlier Factor (LOF) | Density-based; detects local anomalies         |

---

### 5.3 Treatment Strategies

| Strategy                        | When to Use                     | Code Pattern                                       |
| ------------------------------- | ------------------------------- | -------------------------------------------------- |
| **Remove**                | Confirmed data errors           | `df = df[df[col].between(lower, upper)]`         |
| **Cap (Winsorize)**       | Extreme but plausible values    | `df[col] = df[col].clip(lower, upper)`           |
| **Log transform**         | Right-skewed distribution       | `df[col] = np.log1p(df[col])`                    |
| **Square root transform** | Moderate skew                   | `df[col] = np.sqrt(df[col])`                     |
| **Box-Cox**               | Strictly positive; flexible     | `scipy.stats.boxcox(df[col])`                    |
| **Yeo-Johnson**           | Zero or negative values allowed | `sklearn PowerTransformer(method='yeo-johnson')` |

**Geometric interpretation of transforms:** Log and Box-Cox compress the right tail, pulling extreme values closer to the bulk of the distribution. This changes the shape of the feature space from a long ellipsoid into something closer to spherical — the same goal as scaling.

---

## 6. Feature Scaling

> Most ML algorithms operate using **distance** or **gradient** in feature space. Features on different scales distort both.

---

### 6.1 Why Scaling is Necessary

Consider:

```
Feature A: Age       → range [0, 100]
Feature B: Salary    → range [0, 100,000,000]
```

Euclidean distance between two samples:

```
d = sqrt((ΔAge)² + (ΔSalary)²)
           ≈ negligible     ≈ dominates
```

Feature A contributes essentially nothing to any distance computation. The algorithm is operating in a space dominated by Feature B.

**Geometric view:**

```
Unscaled space:                Scaled space:
    ●                              ●  ●
              ●           →     ●     ●
●                              ●  ●
long ellipsoid                 approximate sphere
```

---

### 6.2 Consequences Per ML Paradigm

| Paradigm     | Algorithm                  | Consequence Without Scaling                                                |
| ------------ | -------------------------- | -------------------------------------------------------------------------- |
| Supervised   | KNN                        | Distance dominated by large-scale features                                 |
| Supervised   | SVM (RBF)                  | Kernel distances distorted                                                 |
| Supervised   | Linear/Logistic Regression | Gradient descent converges slowly                                          |
| Supervised   | Neural Network (MLP)       | Slow convergence; unstable training                                        |
| Unsupervised | PCA                        | Variance dominated by large-scale features; principal components biased    |
| Unsupervised | K-Means                    | Euclidean distances distorted; wrong cluster assignments                   |
| Unsupervised | GMM                        | Covariance estimation distorted; numerically unstable                      |
| RL           | Any                        | Large state dimensions dominate policy gradient; slow/unstable convergence |

> **Note:** Tree-based algorithms (Decision Tree, Random Forest, XGBoost) are **invariant to feature scaling** because they split on thresholds, not distances. You may skip scaling for these.

---

### 6.3 Scaling Methods

#### Standardization (Z-score normalization)

```
x' = (x - μ) / σ
```

Result: `mean = 0`, `std = 1`. Does **not** bound values to a fixed range.

```python
from sklearn.preprocessing import StandardScaler
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X_train)
```

**Use when:**

- Distribution is approximately Gaussian.
- No fixed known minimum/maximum.
- Algorithm: Linear/Logistic Regression, SVM, MLP, PCA, K-Means, GMM.
- Default choice when uncertain.

#### Min-Max Scaling

```
x' = (x - x_min) / (x_max - x_min)    →    x' ∈ [0, 1]
```

```python
from sklearn.preprocessing import MinMaxScaler
scaler = MinMaxScaler()
X_scaled = scaler.fit_transform(X_train)
```

**Use when:**

- Feature has a known, meaningful minimum and maximum.
- Neural network uses bounded activation (sigmoid, tanh).
- Image pixel values (0–255 → 0–1).

**⚠️ Sensitive to outliers.** One extreme value compresses all other values. If outliers exist, treat them (Step 5) before applying Min-Max.

#### Robust Scaling (referenced by instructor, not detailed in class)

```
x' = (x - median) / IQR
```

Uses median and IQR instead of mean and std. Inherently outlier-resistant. Appropriate when outliers cannot be removed.

---

### 6.4 Scaling Selection Decision Tree

```
Features have known, fixed bounds AND no significant outliers?
    YES → Min-Max Scaling
    NO  →
        Significant outliers that cannot be removed?
            YES → Robust Scaling
            NO  → Standardization (default)

Additionally:
    Neural network with sigmoid/tanh activations → Min-Max preferred
    PCA, SVM, Linear models, GMM → Standardization
    Tree-based models → No scaling required
```

> **AI Agent Rule:** Always fit the scaler **only** on training data. Apply (transform only) to validation and test data. Never fit on the full dataset — that causes data leakage (Step 10).

```python
# CORRECT
scaler.fit(X_train)
X_train_scaled = scaler.transform(X_train)
X_val_scaled   = scaler.transform(X_val)
X_test_scaled  = scaler.transform(X_test)

# WRONG — leaks test statistics into training
scaler.fit(X_all)
```

---

## 7. Encoding Categorical Variables

> ML models operate on vectors in ℝⁿ. Categorical text labels must be converted to numbers — but the **method** of conversion matters, because it encodes geometric assumptions.

---

### 7.1 Why Encoding Method Matters

Encoding is not just type conversion. It defines the geometric relationship between categories in the feature space. A wrong encoding introduces artificial ordering or artificial distances that the model will learn as if they were real.

---

### 7.2 Label Encoding

```
Red   → 0
Blue  → 1
Green → 2
```

**Problem:** Implies `Green > Blue > Red` and `|Green - Blue| = |Blue - Red|`. If these categories are independent (no natural order), the model learns a false ordinal structure.

**Use only when:** The categories genuinely have a natural order AND the model is tree-based (tree splits ignore the numerical magnitude).

---

### 7.3 Ordinal Encoding

Categories with a true natural ranking:

```
Small  → 0
Medium → 1
Large  → 2
```

This is correct when the order is real. Logically equivalent to Label Encoding but semantically explicit.

```python
from sklearn.preprocessing import OrdinalEncoder
enc = OrdinalEncoder(categories=[['Small', 'Medium', 'Large']])
```

---

### 7.4 One-Hot Encoding

Each category becomes a separate binary dimension:

```
Country  →  Vietnam  Japan  USA
Vietnam      1        0      0
Japan        0        1      0
USA          0        0      1
```

**Advantages:** No false ordering. Geometrically, each category is equidistant from all others.
**Disadvantage:** Dimensionality grows linearly with the number of categories.

```python
from sklearn.preprocessing import OneHotEncoder
enc = OneHotEncoder(sparse_output=False, handle_unknown='ignore')
```

**Drop first category** to avoid the dummy variable trap (perfect multicollinearity) in linear models:

```python
OneHotEncoder(drop='first')
```

---

### 7.5 Soft / Probabilistic Encoding (Instructor's Idea)

Instead of hard one-hot `[1, 0, 0, 0, 0]`, use a soft representation:

```
[0.9, 0.1, 0.1, 0.1, 0.1]  ← Vietnam with soft mass on neighbors
```

**Motivation:** Reduces the effective contribution of the added dimensions while preserving category identity. Related to label smoothing and embedding techniques in deep learning. Useful when one-hot creates severe sparsity.

**Note:** This is not a standard sklearn encoder. Implement as a custom transform or use learned embeddings in a neural network.

---

### 7.6 High-Cardinality Encodings

When a categorical feature has many unique values (e.g., ZIP code, product ID), one-hot encoding is impractical.

#### Frequency / Count Encoding

```
Replace each category with its frequency in the training set.
Vietnam → 0.45  (appears in 45% of rows)
Japan   → 0.30
USA     → 0.25
```

```python
freq_map = df['country'].value_counts(normalize=True)
df['country_freq'] = df['country'].map(freq_map)
```

#### Target Encoding

Replace each category with the mean target value for that category.

```
Vietnam → mean(y | country == Vietnam)
```

**⚠️ Danger: Data leakage.** Must be computed inside cross-validation folds only, never on the full dataset. See Step 10 (Data Leakage) — placeholder.

---

### 7.7 Curse of Dimensionality

One-hot encoding with many categories produces a high-dimensional, sparse feature space.

**Consequences:**

- Distance-based algorithms require exponentially more data to populate the space.
- Memory and compute increase.
- Models need more data to generalize.

**Geometric intuition:** In high dimensions, all points become approximately equidistant. The concept of "nearest neighbor" loses meaning.

### Impact by ML Paradigm

| Paradigm                    | Impact of High Dimensionality                                          |
| --------------------------- | ---------------------------------------------------------------------- |
| Supervised (distance-based) | KNN degrades; SVM kernel bandwidth becomes harder to tune              |
| Supervised (linear)         | Regularization more critical; risk of overfitting                      |
| Supervised (tree)           | Less affected; trees split sequentially and ignore irrelevant features |
| Unsupervised                | PCA becomes necessary; K-Means and GMM cluster quality degrades        |
| RL                          | Observation space explosion; policy learning slows dramatically        |

---

### 7.8 Encoding Selection Decision Tree

```
Does the feature have a natural, meaningful order?
    YES → Ordinal Encoding
    NO  →
        Number of unique categories is small (≤ ~10–15)?
            YES → One-Hot Encoding
                  (if linear model: drop='first' to avoid multicollinearity)
            NO  →
                Target variable is available and leakage is controlled?
                    YES → Target Encoding (inside CV folds only)
                    NO  → Frequency Encoding or Count Encoding
```

**Core principle (instructor):** Minimize the number of dimensions while preserving meaningful information. Never create artificial relationships between independent categories.

---

## 8. Class Imbalance

> A model trained on imbalanced data is not learning the task — it is learning the class distribution.

---

### 8.1 The Problem

Real-world datasets are often dominated by one class:

```
Healthy patients:  99%
Cancer patients:    1%
```

A model that predicts "Healthy" for every sample achieves **99% accuracy** while being completely useless for the actual task (detecting cancer).

**Why this happens:**
Cross-entropy loss (and most loss functions) minimize total error. With 99% healthy samples, always predicting "Healthy" minimizes loss. The model never needs to learn the minority class.

---

### 8.2 Correct Evaluation Requires Non-Accuracy Metrics

| Metric              | What It Measures                                            |
| ------------------- | ----------------------------------------------------------- |
| **Precision** | Of all predicted positives, how many are actually positive? |
| **Recall**    | Of all actual positives, how many were caught?              |
| **F1-Score**  | Harmonic mean of precision and recall                       |
| **ROC-AUC**   | Discrimination ability across all thresholds                |

High accuracy with low recall on the minority class is a **failure mode**, not a success.

> **AI Agent Note:** For imbalanced datasets, always report Precision, Recall, and F1 per class — not just overall accuracy.

---

### 8.3 Solutions

#### Oversampling

Randomly duplicate minority class samples.

```python
# Manual approach
minority = df[df['label'] == 1]
df_balanced = pd.concat([df, minority.sample(n=desired_count, replace=True)])
```

**Downside:** Model may overfit to the exact duplicated samples.

#### SMOTE (Synthetic Minority Over-sampling Technique)

Generate synthetic minority samples by interpolating between existing minority samples in feature space.

```python
from imblearn.over_sampling import SMOTE
sm = SMOTE(random_state=42)
X_res, y_res = sm.fit_resample(X_train, y_train)
```

**Advantage over oversampling:** Creates new examples rather than duplicates; reduces overfitting.
**Constraint:** Apply SMOTE only to training data, never to validation or test.

#### Class Weighting

Tell the loss function to penalize errors on minority classes more heavily.

```python
# Sklearn models
from sklearn.linear_model import LogisticRegression
model = LogisticRegression(class_weight='balanced')

# PyTorch
weight = torch.tensor([1.0, 99.0])  # [majority_weight, minority_weight]
criterion = nn.CrossEntropyLoss(weight=weight)
```

**Advantage:** No resampling needed; works directly on the original dataset.

#### Cost-Sensitive Learning

Assign asymmetric misclassification costs. A false negative (missed cancer) may cost far more than a false positive.

Implement by modifying the loss function or using algorithms that accept a cost matrix.

#### Undersampling

Remove majority class samples until classes are balanced.

**Downside:** Loses potentially useful information. Use only when dataset is very large and information loss is acceptable.

---

### 8.4 RL Analogues (Instructor Mention)

In RL, rare but important transitions (analogous to minority class samples) can be lost in uniform experience replay.

| RL Technique                                  | Analogy                                 |
| --------------------------------------------- | --------------------------------------- |
| **Prioritized Experience Replay (PER)** | Oversample high-error transitions       |
| **ε-greedy exploration**               | Force visits to under-explored states   |
| **Entropy-based exploration**           | Encourage diversity in actions          |
| **UCB (Upper Confidence Bound)**        | Prioritize uncertain state-action pairs |

These are beyond the current course scope but the structural parallel to imbalanced data is exact.

---

## 9. Feature Engineering

> Feature Engineering is the highest-leverage step in classical ML. Better features beat better algorithms.

---

### 9.1 Definition

Feature Engineering is the process of transforming raw data into new representations using domain knowledge, so that the learning algorithm can find patterns more easily.

```
Raw data (pull everything from the source)
    ↓
Domain knowledge + exploratory analysis
    ↓
New features with more predictive signal
    ↓
Better learned representations
    ↓
Higher model performance
```

The information content does not change — only the **representation** changes.

---

### 9.2 ML vs. DL

| Setting                 | Feature Engineering                                                |
| ----------------------- | ------------------------------------------------------------------ |
| **Classical ML**  | Manual. Practitioner designs features from domain knowledge.       |
| **Deep Learning** | Automatic. The network learns hierarchical features from raw data. |

Even in DL, low-level preprocessing (scaling, encoding, handling missing values) still applies. Feature engineering in DL shifts to architecture design and data augmentation.

---

### 9.3 Geometric Interpretation

Each feature is one coordinate axis in feature space.

- **Before feature engineering:** Classes may be entangled in the original coordinate system. No linear boundary can separate them.
- **After feature engineering:** A change of basis (new coordinates) can make classes linearly separable or much easier to cluster.

```
Original space (x₁, x₂):           Engineered space (x₁², x₁·x₂, x₂²):
      class A and B mixed                   class A and B separated
```

A better representation allows even a simple model (linear classifier) to solve a problem that required a complex model in the original space.

---

### 9.4 Common Feature Engineering Operations

| Operation                    | Example                                               |
| ---------------------------- | ----------------------------------------------------- |
| Binning / discretization     | Age →`[0–18, 18–35, 35–60, 60+]`                |
| Date decomposition           | Datetime → Day of week, Month, Season, Hour          |
| Interaction terms            | `Height × Weight → BMI`                           |
| Ratio features               | `Income / Debt → Debt-to-income ratio`             |
| Spatial features             | `(lat, lon) → Distance from city center`           |
| Rolling statistics           | `Transaction history → Avg spend per 30 days`      |
| Log transform                | Compress skewed distributions                         |
| Polynomial expansion         | `x → x, x², x³` for non-linear relationships     |
| Domain-specific aggregations | User behavioral features, product co-occurrence, etc. |

---

### 9.5 What Makes a Feature Good

A useful engineered feature:

- Increases class separability or predictive signal.
- Reduces ambiguity in the input representation.
- Does **not** introduce information that would only be available at inference time (→ data leakage, Step 10).
- Does **not** artificially correlate with the target through the training set statistics (→ target leakage).
- Is interpretable enough to validate with domain knowledge.

---

### 9.6 How Many Features to Start With

> **Instructor recommendation:** Start with 2–3 features. Add more only if performance is clearly insufficient.

**Why small to start:**

- 2–3 features can be directly visualized in 2D or 3D scatter plots — you can *see* whether the features separate classes or clusters.
- Adding features before understanding the data's structure makes debugging much harder.
- For clustering specifically, the problem is fundamentally **space partitioning** — the more dimensions, the harder partitions are to find and interpret (curse of dimensionality, §7.7).

**Workflow:**

```
Start with 2–3 most promising features (use correlation matrix to identify candidates)
    ↓
Visualize — can you see separable structure?
    ↓
Train baseline model
    ↓
Unsatisfactory? Add features incrementally, one at a time
    ↓
Use recursive feature selection or model importance to prune later
```

**For clustering tasks:** your instructor specifically noted that clustering is a space partitioning problem — more features make partition boundaries harder to find and interpret. Prefer fewer, high-signal features over many weakly informative ones. Use silhouette scores (§16.3) to evaluate whether adding a feature actually helps.

---

### 9.7 Feature Selection After Engineering

Creating many candidate features does not mean keeping all of them. After engineering:

1. **Correlation filter:** Remove features with `|r| > 0.95` with another feature (near-duplicate).
2. **Variance threshold:** Remove near-constant features.
3. **Model-based importance:** Use tree feature importances or L1 regularization to identify low-signal features.
4. **Domain sanity check:** Reject features that cannot be computed at inference time.
5. **Recursive feature selection:** Iteratively remove the least important feature and re-evaluate model performance — useful when feature importance scores alone are not decisive.

---

### 9.7 Engineering Workflow

```
1. Collect raw data (pull all available fields from the source)
2. Run EDA (Step 3) — understand what the data represents physically
3. Hypothesize features based on domain knowledge
4. Create candidate features
5. Evaluate signal (correlation with target, model performance delta)
6. Remove redundant or harmful features
7. Repeat before model selection
```

---

### 9.8 Feature Engineering Encompasses More Than New Columns

Feature Engineering is not limited to deriving new columns from existing ones. It includes:

- **Feature construction** — building new features from raw ones (this section).
- **Encoding** — already covered in §7; changes representation without changing information.
- **Dimensionality reduction** (PCA, etc.) — changes the coordinate system itself.
- **Transformation** (log, Box-Cox, Yeo-Johnson) — already covered in §5.3; reshapes a feature's distribution.

All four operations share the same underlying goal stated in §9.3: changing the geometry of the feature space to make the learning task easier.

---

### 9.9 Feature Construction

```
Original feature(s) → construction logic → new feature → fed into model
```

Example: `Income, Debt → Debt-to-Income ratio`

The new feature did not add information that wasn't already present in `Income` and `Debt` — but it re-expresses that information in a form much closer to what actually predicts the target (e.g. loan default).

#### Three Construction Strategies

**1. Relationship features — Ratio & Interaction**

| Type                  | When to Use                                                                                      | Examples                                                                                            |
| --------------------- | ------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------- |
| **Ratio**       | Two features share the same*unit/nature*, differ in scale                                      | `debt / income`, BMI (`weight / height²`), failure rate (`fails / total`)                    |
| **Interaction** | Two features influence each other; their*combined* effect on the target is not simply additive | `age × promotion_eligibility`, `education × income`, `temperature × humidity` (heat index) |

> Ratio features normalize away a confound (e.g. raw debt is meaningless without knowing income). Interaction features capture effects that are linear in neither variable alone — the relationship may be linear *or non-linear*, and is often hard for a plain linear model to discover on its own, which is exactly why it should be engineered explicitly rather than left for the model to find.

**2. Structural features — Aggregation & Time-based**

Used when **one entity has multiple records** (e.g. one customer, many transactions).

*Aggregation:* collapse many records into one statistic per entity.

```
count, sum / mean, min / max, std, P95 / P99 (percentile)
```

Example: A customer has 50 transactions → aggregate into `transaction_count`, `avg_transaction_value`, `std_transaction_value`.

*Time-based features:* exploit *when* events happened, so the model can learn trends rather than just static snapshots.

| Sub-type           | Description                                 | Example                                    |
| ------------------ | ------------------------------------------- | ------------------------------------------ |
| Calendar features  | Extract structured time components          | day-of-week, month, is_weekend, is_holiday |
| Lag features       | Value of a variable at a previous time step | `sales_t-1`, `sales_t-7`               |
| Rolling features   | Moving statistic over a window              | 7-day rolling average                      |
| Time difference    | Elapsed time between two events             | days since last purchase                   |
| Frequency features | How often an event recurs                   | logins per week                            |

**Use when:** the dataset has a timestamp and order matters.

**3. Geometric / Polynomial features**

```
(x, y)  →  (x, x², y, x·y, ...)
```

**Idea:** add powers and products of existing features to project the data into a higher-dimensional space, where a relationship that is non-linear in the original space becomes linear (or closer to linear) in the new space.

**Use when:**

- EDA (§3) reveals a clearly non-linear relationship.
- A linear model underfits the data.
- You want to keep the simplicity/interpretability of a linear model while increasing its representational power.

**⚠️ Major risk:** Polynomial expansion grows the feature space combinatorially (degree-2 expansion of `n` features produces `O(n²)` new features). This:

- Increases overfitting risk sharply (more parameters relative to data).
- Triggers the curse of dimensionality (§7.7).
- Should always be paired with regularization (see §15) and validated with cross-validation (§17), never trusted on train-set performance alone.

#### Summary Flow

```
Raw data
    ↓  domain knowledge + human understanding
Feature Engineering (construction + encoding + transformation + dimensionality reduction)
    ↓
Optimized feature space
    ↓
Effective model
```

---

## 10. Train / Test Split and Data Leakage

> This is the stage most commonly implemented incorrectly — including in earlier versions of this exact project. Read this section carefully before touching any preprocessing code.

---

### 10.0 Common Confusion — "Can I Apply Feature Engineering to the Test Set?"

**Short answer: Yes — but only the *application*, never the *fitting*.**

This is the exact confusion your notes flagged: "you told me not to touch the test set at all — so how can I apply FE to it?"

The resolution is a distinction between two types of FE operations:

#### Type A — Statistic-free transformations (safe to apply identically to both sets)

These operations do not require any fitted parameter from the data. You compute them the same way on train and test with no risk of leakage:

| Operation                | Example                     | Why it's safe                           |
| ------------------------ | --------------------------- | --------------------------------------- |
| Ratio of two raw columns | `debt / income`           | No statistics needed — just arithmetic |
| Polynomial expansion     | `x² = x * x`             | Pure math on each row independently     |
| Date decomposition       | `datetime → day_of_week` | Deterministic, no fitting               |
| Log transform            | `log(x + 1)`              | Same function applied to every value    |

For these, you apply the identical formula to both train and test. There is nothing to "fit" — so there is no leakage risk.

#### Type B — Statistic-dependent transformations (fit on train, apply to test)

These require a parameter derived from the data (a mean, a frequency, a min/max). The rule is:

```
Compute the parameter from TRAIN only
    ↓
Apply using that parameter to TRAIN → transformed train
    ↓
Apply using that SAME parameter to TEST → transformed test
                    ↑
            never recompute this on test data
```

| Operation          | What is "fitted"                            | Leakage risk if done wrong                        |
| ------------------ | ------------------------------------------- | ------------------------------------------------- |
| StandardScaler     | mean and std from training data             | Using global mean/std includes test distribution  |
| Mean imputation    | mean of the training column                 | Using global mean shifts the test imputed values  |
| Frequency encoding | category frequencies from training data     | Test frequencies may differ → inflated knowledge |
| Target encoding    | target mean per category from training data | Direct leakage of y values into features          |

#### The practical rule

> **"Apply FE to the test set using the test set's own raw columns, but any statistics used in that FE must come from the training set only."**

The test set is not "untouchable" — it just cannot *inform* any decisions made during preprocessing. You are allowed to transform it; you are not allowed to learn from it.

#### Why DL handles this automatically

In a neural network, feature extraction (convolution, attention, learned embeddings) happens inside layers that are trained only on the training set. When you run inference on the test set, the same *weights* (the network's "fitted parameters") are applied — exactly parallel to applying a train-fitted scaler to the test set. The principle is identical; DL just enforces it structurally so you can't accidentally break it.

---

### 10.1 Why Split Before Transforming?

**Question:** Why must the data be split *before* any preprocessing?

**Answer:** The test set must represent a genuinely unknown future. If any information from the test set leaks into how the training data is processed — even indirectly, through a statistic like a global mean — the evaluation becomes optimistic and dishonest. The model is no longer being tested on truly unseen data.

#### Correct order

```
Split (train / test)
    ↓
Fit transformation parameters on TRAIN ONLY
    (mean, std, min/max, category frequency, target-encoding map, etc.)
    ↓
Transform train set using those parameters
    ↓
Transform test set using the SAME parameters (no refitting)
    ↓
Train model on transformed train set
    ↓
Evaluate on transformed test set
```

#### Why this matches Deep Learning naturally

In an end-to-end neural network (e.g. raw image pixels → CNN → classification), feature extraction happens *inside* the network during training on the train set only. The network never "sees" test-set statistics before evaluation. Classical ML pipelines must enforce this same discipline manually, because preprocessing is a separate, explicit step.

#### What leakage looks like (the bug to avoid)

```
❌ WRONG:
1. Compute mean/std on the FULL dataset (train + test combined)
2. Scale the full dataset using those statistics
3. THEN split into train/test
4. Train and evaluate

Problem: test-set values influenced the mean/std used to scale the
training data. The model indirectly "saw" the test distribution
before evaluation. Reported test accuracy will be optimistically biased.
```

```
✅ CORRECT:
1. Split into train/test FIRST
2. Compute mean/std on TRAIN ONLY
3. Apply those train statistics to both train and test
4. Train and evaluate
```

This exact pattern applies to **every** fitted preprocessing step: scaling (§6), imputation (§4), encoding (§7), outlier bounds (§5), and feature construction ratios that use global statistics (§9.9).

---

### 10.2 The Golden Rules

1. **Split first, compute statistics second.** No exceptions.
2. **The test set must remain independent and untouched** until final evaluation.
3. **Every statistical parameter (mean, std, encoding map, IQR bounds, etc.) is computed from the training set only.**
4. **The test set is evaluated exactly once, at the end.** Repeatedly checking test performance during development and adjusting based on it is itself a form of leakage (you are indirectly fitting to the test set through your own decisions).

> **[inference — verify in class]** Rule 4 is standard ML methodology (sometimes called "test set contamination through repeated peeking"). Your note mentions evaluating "by the test set only once at the end" — this is consistent with that principle. If hyperparameter tuning is needed, use a separate validation set or cross-validation (§17) on the *training* portion, never the test set.

---

### 10.3 Why Random Split Is Not Always Enough

A naive random split can break the underlying probability structure of the data.

**Example:** If the full dataset is 90% class A / 10% class B, a random split *could*, by chance, produce a train set that is 95%/5% and a test set that is 80%/20% — the test set no longer represents the same distribution the model was trained on, making evaluation misleading.

#### Stratified Split

Preserves the original class (or cluster) proportions in both train and test sets.

```
Full dataset:  90% A / 10% B
    ↓ stratified split
Train set:     90% A / 10% B   (same ratio)
Test set:      90% A / 10% B   (same ratio)
```

**When to use:** Classification tasks, imbalanced data (§8), clustering/density-based unsupervised tasks where class or cluster proportions matter for fair evaluation.

```python
# Manual stratified split (no sklearn)
def stratified_split(X, y, test_ratio=0.2, seed=42):
    rng = np.random.default_rng(seed)
    train_idx, test_idx = [], []
    for cls in np.unique(y):
        cls_idx = np.where(y == cls)[0]
        rng.shuffle(cls_idx)
        n_test = int(len(cls_idx) * test_ratio)
        test_idx.extend(cls_idx[:n_test])
        train_idx.extend(cls_idx[n_test:])
    return np.array(train_idx), np.array(test_idx)
```

#### Time Series Split

For temporally ordered data, samples must be split along the time axis — never shuffled randomly.

```
[ -------- train (past) -------- ][ -------- test (future) -------- ]
                                  ↑
                            split point (chronological)
```

**Problem to avoid — look-ahead bias:** If future information leaks into the training set (e.g. a randomly shuffled split puts a "future" sample in train and a "past" sample in test), the model is implicitly trained using information that would not have been available at prediction time in a real deployment. This silently inflates reported performance and produces a model that fails in production.

#### Time Series: Data Problems Matter More Than Model Complexity

Your instructor noted this explicitly: in time series tasks, most problems come from **data quality and ordering issues**, not from model complexity. Before tuning any hyperparameter, verify:

- The time ordering of records is strictly preserved (no accidental shuffles in loading/preprocessing).
- Lag features and rolling statistics are computed using only past observations relative to each row — never future ones.
- The train/test split boundary is a single chronological point, not a random sample.

#### Split Strategy Decision Tree

```
Does the data have a time/ordering component (timestamps, sequential events)?
    YES → Time Series Split (chronological, never shuffled)
          Focus first on data integrity, not model complexity.
    NO  →
        Does the data have labels (classification) or meaningful
        group/cluster structure that should be preserved in proportion?
            YES → Stratified Split
            NO  → Random Split
```

---

## 11. Baseline Thinking

> A complex model is meaningless if it cannot beat a simple rule.

---

### 11.1 The Problem With Skipping Baselines

Jumping straight to a complex model without first establishing a baseline causes:

- **Wasted time and resources** — tuning a deep model when a simple one might suffice.
- **Inability to judge real improvement** — without a reference point, a "good" metric value has no meaning.
- **Performance illusions** — a complex model may *appear* to perform well in isolation while actually doing no better (or worse) than a trivial rule.

This is exactly why a model survey — comparing simple to complex — must happen before committing resources to any one approach.

### 11.2 Core Value of a Baseline

1. **Lower bound / minimum standard** — any model must clear this bar to be worth using.
2. **Fair comparison across models** — every candidate model is judged against the same reference.
3. **Resource efficiency** — avoids over-investing in complexity before confirming it's needed.
4. **Foundation for iterative improvement** — subsequent models are evaluated as deltas over the baseline, not in a vacuum.

### 11.3 Define Objectives and Constraints Before Choosing a Baseline

> **Instructor emphasis:** Identify your goals and constraints at the very start of the project — not after you've already trained a model.

Before selecting any baseline, answer:

- **Time constraint:** How long can training realistically take per experiment run?
- **Compute constraint:** What hardware is available? Can you afford to retrain a large model 20 times during hyperparameter tuning?
- **Accuracy requirement:** Is 90% good enough for this use case, or does the task demand 99%+?
- **Interpretability requirement:** Does the domain (law, medicine, finance) require an explainable model over a black-box one?

These constraints directly affect what counts as a "reasonable" baseline and whether a complex model is even worth pursuing.

### 11.4 How to Choose a Baseline

**Instructor recommendation (in the context of a course / standard ML project):**

> Start with the simplest model. Do not skip traditional/classical models.

The baseline does **not** need to be the newest or most accurate model from recent research — that is a research context concern. In an ML project, the baseline's job is to set a floor you can clearly beat, not to impress anyone.

| Context                   | Recommended Baseline Approach                                                          |
| ------------------------- | -------------------------------------------------------------------------------------- |
| Course / student project  | Simplest model for the task (logistic regression, single Gaussian, random policy)      |
| Industry ML project       | Best simple model that is already in production, or a well-known statistical heuristic |
| Scientific research paper | Best-performing*published* model on the same benchmark dataset                       |

**The baseline is also the foundation for error analysis (§19):** comparing your main model's errors against the baseline's errors using the 5W framework (What failed? Where? When? Why? Who/which subgroup?) reveals whether improvements are real or just noise.

### 11.5 Baseline Choices Per Pillar

| Paradigm               | Typical Baseline                                                                                                                                      |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Supervised             | Logistic Regression / Linear Regression with default hyperparameters                                                                                  |
| Unsupervised           | K-Means with small`k` (your instructor's note ended with "?" — treat as *start simple and justify your k choice using silhouette/elbow, §16.3*) |
| Reinforcement Learning | Random policy, or a simple rule-based / heuristic policy                                                                                              |

### 11.6 The Cost of Repeated Baseline Comparisons in DL

Your note flags a real concern: if the baseline involves a DL model, retraining it many times during development is expensive.

Practical mitigations:

- Use a much simpler model (logistic regression, small MLP) as the baseline — not a full DL model — so retraining is cheap.
- Cache baseline results. Once the baseline is trained and evaluated on the fixed test set, you don't retrain it — you just compare new models against the stored number.
- Use K-Fold CV (§17) on the training set for new model variants, compare μ±σ against baseline μ±σ, without retraining the baseline each time.

### 11.8 Cost-Benefit Decision Rule

Before accepting a more complex model over the baseline, ask: **is the improvement worth the added cost (compute, complexity, maintainability, interpretability loss)?** A 0.01 metric improvement rarely justifies a 10× increase in model complexity.

```
Compare candidate model performance to baseline:

(a) Does NOT beat baseline
        → Return to EDA. Re-examine data, features, or try a
          fundamentally different model family.

(b) Slightly beats baseline
        → Investigate the trade-off. Run cross-validation (§17)
          to confirm the improvement is stable, not noise.

(c) Clearly beats baseline
        → Proceed with further development of this model.
```

---

## 12. No Free Lunch Theorem

> There is no algorithm that is optimal for every problem — only algorithms that are well-matched to specific data.

### 12.1 Core Idea

Choosing an algorithm is fundamentally about finding compatibility between:

- The **mathematical assumptions** built into the model (its *inductive bias*).
- The **geometric structure** of the actual data.

### 12.2 Formal Statement (Informal Summary)

Averaged across *all possible problems*, every algorithm performs equally well (and equally poorly):

```
Σ P(success | algorithm A, problem distribution) = Σ P(success | algorithm B, problem distribution)
```

**Interpretation:** Gains on one type of problem are offset by losses on another. There is no universally superior algorithm — only algorithms suited to the structure of the specific data you actually have.

### 12.3 Inductive Bias

Every algorithm carries built-in assumptions about what "good" structure in the data looks like:

| Algorithm         | Inductive Bias (Assumption About Data)                     |
| ----------------- | ---------------------------------------------------------- |
| K-Means           | Clusters are roughly spherical and well-separated          |
| Linear Regression | Relationship between features and target is linear         |
| Decision Tree     | Decision boundaries are axis-aligned splits                |
| GMM               | Data is generated from a mixture of Gaussian distributions |
| KNN               | Similar points (by distance) have similar labels/values    |

**Implication:** If your EDA (§3) shows clusters that are non-spherical or elongated, K-Means' inductive bias is mismatched to your data — no amount of tuning will fix a fundamentally wrong assumption. This is why §3 (geometric data survey) must come before model selection.

### 12.4 Algorithm Selection Procedure

```
1. Understand the data's structure thoroughly (§3 — EDA)
2. Define the objective and constraints (accuracy target, latency, interpretability needs)
3. Choose an appropriate baseline (§11)
4. Evaluate candidates empirically — not by reputation or popularity
5. Select and fine-tune intelligently, guided by steps 1–4
```

---

## 13. Bias–Variance Tradeoff

### 13.1 Decomposition

```
Total Error  =  Bias²  +  Variance  +  σ² (irreducible noise)
```

| Term                         | Meaning                                                                    | Symptom                                |
| ---------------------------- | -------------------------------------------------------------------------- | -------------------------------------- |
| **Bias²**             | Error from overly simplistic assumptions; model can't capture true pattern | **Underfitting**                 |
| **Variance**           | Error from excessive sensitivity to training data fluctuations             | **Overfitting**                  |
| **σ² (irreducible)** | Inherent noise in the data/process itself; no model can remove this        | Sets the theoretical performance floor |

**Goal:** Minimize `Bias² + Variance` jointly — there is a tradeoff between them, and the "sweet spot" is where their sum is lowest (irreducible noise is, by definition, out of your control).

```
Model complexity →

High Bias, Low Variance  |  Sweet Spot  |  Low Bias, High Variance
     (underfit)           (best total)         (overfit)
```

### 13.2 General Design Loop

```
Data → Model → Train → Evaluate (measure bias, variance, generalization gap)
    ↓
Adjust model complexity / regularization
    ↓
Repeat
```

The "generalization gap" — the difference between train performance and validation/test performance — is the practical signal used to diagnose bias vs. variance:

```
Train error high, gap small  → high bias (underfitting)
Train error low, gap large   → high variance (overfitting)
Train error low, gap small   → good fit (near sweet spot)
```

---

## 14. Hyperparameters vs. Parameters

|                     | Hyperparameters                                                           | Parameters                                            |
| ------------------- | ------------------------------------------------------------------------- | ----------------------------------------------------- |
| **Set by**    | Human, before training                                                    | Model, during training                                |
| **Examples**  | learning rate, number of layers,`k` in K-Means, regularization strength | weights, biases, cluster centroids (final values)     |
| **Tuned via** | Search procedures (grid/random search, manual tuning)                     | Gradient descent, EM algorithm, closed-form solutions |

---

## 15. Hyperparameter Tuning

### 15.1 Regularization Strength

```
Regularization ↑  →  Variance ↓, Bias ↑  →  risk of underfitting if too strong
Regularization ↓  →  Variance ↑, Bias ↓  →  risk of overfitting if too weak
```

Regularization (L1/L2 penalty, dropout, weight decay) constrains the model's effective complexity, directly trading variance for bias.

### 15.2 Model Complexity (e.g. `k` in KNN/K-Means, `max_depth` in trees)

```
Complexity ↑  →  Variance ↑, Bias ↓  (model fits training data more tightly)
Complexity ↓  →  Variance ↓, Bias ↑  (model is more constrained/simplistic)
```

**Correction to your note:** the relationship is the *opposite* direction from regularization — increasing model complexity (deeper trees, larger `k` neighborhoods... careful: for KNN specifically, larger `k` actually *smooths* the decision boundary, *decreasing* variance — the direction depends on what "complexity" means for that specific hyperparameter). **[inference — verify in class]** Always reason from the specific hyperparameter's effect on the model's effective capacity, not from a single universal rule. General principle: anything that lets the model fit the training data more tightly increases variance and decreases bias; anything that constrains the model does the opposite.

### 15.3 Learning Rate *(your notes marked this as "failed to noted" — filled from general theory, [inference — verify in class])*

Learning rate controls the step size in gradient-based optimization (e.g. MLP training).

```
Learning rate too high  →  Loss oscillates or diverges; optimizer overshoots minima
Learning rate too low   →  Convergence is very slow; risk of getting stuck in
                            poor local minima within a limited training budget
Learning rate "just right" → Smooth, efficient convergence to a good minimum
```

Unlike regularization or model complexity, learning rate does not directly trade bias for variance — it governs *optimization dynamics* (whether and how efficiently the model reaches a good solution at all), not the model's representational capacity.

### 15.4 Hyperparameter Engineering Workflow

```
Data
  ↓
Model selection (§12 — No Free Lunch)
  ↓
Choose hyperparameter search space
  ↓
Train / Evaluate (using validation set or K-Fold CV — §17, NEVER the test set)
  ↓
Analyze results (bias/variance diagnosis — §13)
  ↓
Tune & repeat
```

---

## 16. Evaluation Metrics

### 16.1 Supervised — Classification

| Metric                     | Formula / Definition                    | What It Captures                                                              |
| -------------------------- | --------------------------------------- | ----------------------------------------------------------------------------- |
| Confusion Matrix           | TP / FP / TN / FN counts                | Raw breakdown of all prediction outcomes                                      |
| Accuracy                   | `(TP + TN) / total`                   | Overall correctness —**misleading under class imbalance**, see §8.2   |
| Precision                  | `TP / (TP + FP)`                      | Of predicted positives, how many are actually positive                        |
| Recall (Sensitivity / TPR) | `TP / (TP + FN)`                      | Of actual positives, how many were correctly found                            |
| F1-Score                   | `2 × (P × R) / (P + R)`             | Harmonic mean of precision and recall                                         |
| Specificity (TNR)          | `TN / (TN + FP)`                      | Of actual negatives, how many were correctly identified                       |
| FPR (False Positive Rate)  | `FP / (FP + TN)`                      | Rate at which negatives are incorrectly called positive                       |
| ROC Curve                  | TPR vs. FPR at every threshold          | Full picture of discrimination across all thresholds                          |
| ROC-AUC                    | Area under the ROC curve                | Single-number summary of discrimination ability (0.5 = random, 1.0 = perfect) |
| Precision-Recall Curve     | Precision vs. Recall at every threshold | Better than ROC when positive class is rare                                   |
| PR-AUC                     | Area under the PR curve                 | Preferred over ROC-AUC under severe class imbalance                           |

**When to use which curve:**

```
Class distribution roughly balanced?
    YES → ROC curve + AUC is informative
    NO  → Use Precision-Recall curve + PR-AUC instead
          (ROC-AUC can appear high even when the model fails badly on the minority class)
```

### 16.2 Supervised — Regression

| Metric                             | Formula / Description                                             |
| ---------------------------------- | ----------------------------------------------------------------- |
| MAE (Mean Absolute Error)          | `mean(\|y - ŷ\|)` — robust to outliers                          |
| RMSE (Root Mean Squared Error)     | `sqrt(mean((y - ŷ)²))` — penalizes large errors more heavily |
| R² (Coefficient of Determination) | Proportion of variance in`y` explained by the model             |

### 16.3 Unsupervised

| Metric                   | What It Captures                                                      | Direction                             |
| ------------------------ | --------------------------------------------------------------------- | ------------------------------------- |
| Silhouette Score         | How cohesive and well-separated clusters are (-1 to 1)                | Higher is better                      |
| Elbow Method (inertia)   | Within-cluster sum of squares vs. k                                   | Look for the "elbow" inflection point |
| Davies–Bouldin Index    | Average similarity between each cluster and its most similar neighbor | Lower is better                       |
| Calinski–Harabasz Index | Ratio of between-cluster to within-cluster dispersion                 | Higher is better                      |

#### Silhouette vs. Elbow Conflict

When silhouette score and the elbow method suggest **different values of k**, this is the resolution:

> **Prioritize the silhouette score.** The elbow method is heuristic and subjective — the "elbow" is often ambiguous. Silhouette directly measures cluster quality as experienced by the data.

**However:** if both metrics disagree sharply, this is a signal that **the data itself may have a problem** — not just a tie-breaking question. Likely causes:

- The features do not actually form separable clusters (wrong algorithm choice, §12).
- The feature space is too high-dimensional (§9.6 — reduce features first).
- There is a data quality issue (noise, outliers, bad scaling) masking the true structure.

**Action when you see a silhouette vs. elbow conflict:**

```
1. Return to EDA (§3) and re-examine the data's geometric structure
2. Verify feature scaling was applied correctly (§6)
3. Try reducing to 2-3 features and visualize directly
4. Consider whether clustering is even the right approach for this data
```

#### Explaining Every Benchmark Number — the 5W Rule

> **Instructor emphasis:** For every metric value you report, you must be able to explain it.

Apply the 5W framework to every performance number:

- **What** metric is this, and what does it actually measure?
- **Where** in the pipeline was it computed (which dataset, which fold)?
- **When** — at what training stage / iteration?
- **Why** is this number higher or lower than expected / than the baseline?
- **Which** subgroup, class, or cluster does this number come from (aggregate numbers can hide subgroup failures)?

A number without a 5W explanation is not a result — it is an observation without understanding.

### 16.4 Reinforcement Learning

| Metric            | What It Captures                                                     |
| ----------------- | -------------------------------------------------------------------- |
| Average Return    | Mean reward per episode                                              |
| Cumulative Reward | Total reward accumulated over training/episode                       |
| Episode Length    | How long the agent survives/operates per episode                     |
| Success Rate      | Fraction of episodes meeting the task's success criterion            |
| Sample Efficiency | How much reward is achieved per unit of training data/experience     |
| Regret            | Cumulative gap between achieved reward and optimal achievable reward |

---

## 17. Cross-Validation (K-Fold)

### 17.0 Terminology Note — "K-Fold" vs. "F-Fold"

Your notes record "F-Fold" with a question mark. This is almost certainly the same concept as K-Fold cross-validation — the letter used for the number of folds varies by source (`K`, `F`, `N` are all used interchangeably in different textbooks and courses). In data mining literature specifically, `k` is also used as a variable for cluster count (in K-Means), so some instructors use `F` for folds to avoid the naming collision. The algorithm is identical regardless of the letter.

---

### 17.1 Why a Single Split Is Not Enough

Two different random train/test splits of the *same* dataset can produce noticeably different evaluation results purely by chance — particularly with smaller datasets. A single split gives you one noisy sample of "how good is this model," not a reliable estimate.

### 17.2 K-Fold Mechanism

**Critical scope rule:** K-Fold CV operates *only within the training set* (established by the train/test split in §10). The test set remains held out entirely, untouched until final evaluation.

```
Training set
    ↓ split into K equal folds
[Fold 1][Fold 2][Fold 3]...[Fold K]

For each of K rounds:
    Hold out one fold as the validation fold
    Train on the remaining K-1 folds
    Evaluate on the held-out fold

Result: K independent performance scores → mean ± std
```

### 17.3 Variants

| Variant                      | When to Use                                                                                                                                   |
| ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| **K-Fold (standard)**  | Default for i.i.d. data with no class or time structure to preserve                                                                           |
| **Stratified K-Fold**  | Classification / imbalanced data — preserves class proportions in every fold                                                                 |
| **Time Series K-Fold** | Temporal data — each fold's validation portion must be chronologically*after* its training portion (no look-ahead, consistent with §10.3) |

### 17.4 Reporting Results — Scientific Standard

Report results as `μ ± σ` (mean ± standard deviation) across folds, not a single number.

```
Accuracy: 0.873 ± 0.012
```

**Interpreting σ (stability of the result):** **[inference — verify in class against the exact thresholds your instructor uses]**

| σ range              | Interpretation                                                                                                                                           |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `σ < 0.02`         | Small variation — result is stable across folds                                                                                                         |
| `0.02 ≤ σ < 0.05` | Medium variation — moderately stable, worth noting                                                                                                      |
| `σ ≥ 0.05`        | Large variation — result is unstable; treat the mean with caution and investigate why (small dataset? poor fold balance? high model variance per §13?) |

### 17.5 Standard ML Workflow Incorporating CV

```
Full dataset
    ↓
Train / Test split (§10 — test set sealed away)
    ↓
Within Train set: Validation set OR K-Fold CV
    ↓
Select hyperparameters (§15) using CV results only
    ↓
Train final model on full training set with selected hyperparameters
    ↓
Analyze
    ↓
(repeat tuning loop as needed — NEVER touching the test set)
    ↓
Final, single evaluation on the held-out test set
```

---

## 18. Scientific Experimental Methodology

### 18.1 The Problem With Unstructured Trial-and-Error

> "Changing too many things at once means you don't know what actually caused a change — improvement or degradation — in the model's results."

This is the core failure mode of unstructured experimentation: results become unattributable, and conclusions drawn from them are unreliable.

### 18.2 The Scientific Method Applied to ML Experiments

```
1. Observation     — form a hypothesis, understand the problem/symptom
2. Question        — state precisely what you want to find out
3. Experiment      — change exactly ONE factor
4. Evaluation      — measure the effect using cross-validation (§17), not a single run
5. Conclusion      — draw conclusions strictly from the data/results obtained
6. New Hypothesis  — based on the conclusion, propose the next question
```

This loop repeats — it is iterative, not a one-shot process.

### 18.3 The Single-Variable Principle

> **"Hold everything else constant. Change only one thing."**

This is the same logic as a controlled experiment in natural science. If you change the learning rate *and* the regularization strength *and* the architecture in the same run, and the result improves, you cannot determine which change was responsible — or whether the changes partially canceled each other out.

**Practical implication for code:** Log every hyperparameter and configuration value alongside every result. Never modify more than one configuration value between logged experiment runs.

### 18.4 Statistical Validation *(brief — your notes marked this incomplete)*

Your notes mention p-values with the caveat that "p-values are not always suitable." This is a real and well-known limitation — p-values are sensitive to sample size and don't directly measure effect size. **[inference — verify in class]** Common complementary or alternative approaches:

- **t-test** — tests whether the difference between two models' mean performance (e.g. across K-Fold results) is statistically significant.
- **Bootstrap resampling** — repeatedly resample the dataset with replacement to build an empirical distribution of a metric, from which a confidence interval can be derived without strong distributional assumptions.
- **Confidence intervals** — a range, rather than a single point estimate, expressing the uncertainty around a metric (related to the `μ ± σ` reporting standard in §17.4).

This subsection is intentionally minimal — your lecture notes indicate this topic was not fully covered. Treat it as a pointer for further reading, not a complete reference.

---

## 19. Error Analysis

> Error analysis is the systematic study of *where and why* a model fails — not just *how often*. A model with 95% accuracy can still be systematically failing on the cases that matter most.

The baseline model (§11) is the starting point for error analysis: you compare the main model's errors against what the baseline already got wrong, to identify whether your improvements are real or just redistribution of the same mistakes.

---

### 19.1 Process for Labeled Data (Supervised Learning)

```
Step 1 — Extract errors
         Collect all misclassified samples (FP, FN) or high-residual samples
         (regression). Do not look at correct predictions — focus only on failures.

Step 2 — Inspect error samples
         - Visual inspection for image/signal data
         - Read/manually review for text data
         - Use an LLM to help categorize patterns across large error sets
         - Look for clusters of similar errors

Step 3 — Group errors by root cause
         Assign each error (or error pattern) to a category:

         | Root Cause | Description | Example |
         |------------|-------------|---------|
         | Missing feature / information | The model couldn't have known — the signal isn't in the data | Predicting disease without access to patient history |
         | Label noise / wrong labels | The training label itself was wrong | Survey annotations with ~10–20% error rate (see note below) |
         | Class imbalance | Minority class systematically under-predicted | Cancer cases lost in a 99%/1% dataset |
         | Outliers / noisy data | Individual corrupted or extreme samples | Sensor glitches, data entry errors |
         | Rare labels / distribution shift | Label types seen rarely in train, frequently in test | Seasonal patterns, edge-case categories |
         | Low data quality | Degraded input quality | Blurry images, truncated text, low-resolution signals |

Step 4 — Prioritize actions
         Rank error groups by: frequency × severity of failure.
         Fix the most common, highest-impact root cause first.
         Do not scatter effort across all error types simultaneously.
```

#### On Label Noise — Instructor's Note

> Your instructor cited surveys showing that public datasets have approximately **10–20% mislabeled samples**. The target minimum is **≤5% label error rate** before a dataset is considered reliable for training.

This means: before blaming your model for failures, verify your labels. Noisy labels can make it impossible to exceed a certain accuracy ceiling regardless of model complexity — a ceiling that looks like a model problem but is actually a data problem.

---

### 19.2 Process for Reinforcement Learning

> **"Don't just look at the reward — look at the agent's behavior itself."**

The cumulative reward number alone is insufficient for RL error analysis. Examine:

```
1. Low reward episodes
         → When does the agent consistently fail to accumulate reward?
           Is it systematic (a specific state type) or random?

2. Repetitive actions with no meaningful gain
         → Agent is stuck in a local loop. Indicates policy is trapped
           in a degenerate sub-optimal strategy.

3. Dead states
         → Agent reaches an unrecoverable state. Examine why and how
           often. May indicate a missing constraint or reward signal.

4. Rare scenarios
         → States or transitions the agent almost never encounters during
           training but may face in deployment. High-risk blind spots.
```

Further RL error analysis steps (your notes marked these as partially recorded — treat as pointers for further study):

- **Analyze model trajectory:** examine the sequence of states and actions over full episodes, not just final reward.
- **Find the root cause:** trace bad episodes backward to the decision point where the agent diverged from a good path.
- **Act carefully:** because RL policies can interact with environments in unexpected ways, verify fixes in a controlled test environment before broader deployment.

---

### 19.3 The 5W Framework for All Benchmarks

> **Instructor emphasis:** Every metric, every benchmark number, every performance result must be explainable. A number without an explanation is an observation without understanding.

For every reported result, answer:

| W               | Question                                                                                                       |
| --------------- | -------------------------------------------------------------------------------------------------------------- |
| **What**  | What metric is this, and what does it actually measure in this context?                                        |
| **Where** | Which dataset, which partition (train/val/test), which fold?                                                   |
| **When**  | At what training step, epoch, or EM iteration was this recorded?                                               |
| **Why**   | Why is this number higher or lower than the baseline or expected value?                                        |
| **Which** | Which subgroup, class, cluster, or time period does this apply to? (Aggregate numbers hide subgroup failures.) |

This framework is especially important when there are **discrepancies between metrics** — e.g. high accuracy but low recall, or different k giving conflicting silhouette vs. elbow results (§16.3). The discrepancy is the most informative signal. Explain it before moving on.

---

## 20. Model Interpretability *(brief — terms marked "forgot to noted" in your notes; standard definitions given, [inference — verify in class])*

### 20.1 Why It Matters

Deep Learning models are often "black boxes" — their internal decision logic is not directly human-readable. In domains with legal, medical, or financial consequences, an unexplainable decision can be a serious liability (regulatory non-compliance, inability to justify a denied loan or diagnosis, etc.). This is a major reason classical, more interpretable ML models are still preferred in those domains over deep learning, even when DL might achieve marginally higher accuracy.

### 20.2 Global vs. Local Interpretability

| Type             | Question Answered                                                                | Example Technique                                       |
| ---------------- | -------------------------------------------------------------------------------- | ------------------------------------------------------- |
| **Global** | How does the model behave*overall*, across the entire feature space?           | Feature importance rankings, partial dependence plots   |
| **Local**  | Why did the model make*this specific* prediction for *this specific* sample? | SHAP values, LIME, single-decision-tree-path inspection |

---

## Instructor's Final Pipeline Summary (As-Given)

Your instructor's own end-of-course summary of the pipeline, reproduced as given, with cross-references into this document:

| #  | Stage                                                           | See Section   |
| -- | --------------------------------------------------------------- | ------------- |
| 1  | EDA                                                             | §3           |
| 2  | Cleaning                                                        | §4, §5      |
| 3  | Feature Engineering (includes encoding, transformation)         | §6, §7, §9 |
| 4  | Data Split                                                      | §10          |
| 5  | Baseline Model                                                  | §11          |
| 6  | Model Selection                                                 | §12          |
| 7  | Hyperparameter Tuning                                           | §14, §15    |
| 8  | Train Model                                                     | —            |
| 9  | Evaluation Metrics                                              | §16          |
| 10 | Cross-Validation                                                | §17          |
| 11 | Experiments Management                                          | §18          |
| 12 | Statistical Validation (t-test, bootstrap, confidence interval) | §18.4        |
| 13 | Error Analysis                                                  | §19          |
| 14 | Model Interpretability                                          | §20          |

> **Note on ordering:** This instructor summary places Feature Engineering *before* Data Split, and lists Scaling/Encoding as part of Feature Engineering rather than separate stages. This document's detailed sections (§4–§9) describe scaling, encoding, and imputation as if computed before the split for conceptual clarity — but per §10's Golden Rules, in actual implementation the *fitting* of every transformation must happen strictly after the split, on the training partition only. Conceptual order (this document) and implementation order (fit-after-split) are not the same thing — do not confuse them.

---

## Appendix: Common API Patterns for the Pipeline

> **⚠️ Reminder:** The code below uses scikit-learn / imblearn for clarity of *concept only*. If your project requires implementation from scratch (e.g. a from-scratch course constraint), translate every call below into the equivalent NumPy math — do not import these libraries directly. See your project-specific refactor prompts for the from-scratch version.

```python
import numpy as np
import pandas as pd
from sklearn.impute import SimpleImputer, KNNImputer
from sklearn.preprocessing import (
    StandardScaler, MinMaxScaler, RobustScaler,
    OrdinalEncoder, OneHotEncoder, PowerTransformer
)
from imblearn.over_sampling import SMOTE

# 1. Load and inspect
df = pd.read_csv('data.csv')
print(df.shape, df.dtypes, df.isnull().sum(), df.describe())

# 2. Split features by type
num_cols = df.select_dtypes(include='number').columns.tolist()
cat_cols = df.select_dtypes(include='object').columns.tolist()

# 3. SPLIT FIRST (see §10 — this must happen before any fitting below)
from sklearn.model_selection import train_test_split
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42, stratify=y  # stratify if classification
)

# 4. Outlier detection (IQR) — compute bounds from TRAIN only
def iqr_bounds(series):
    Q1, Q3 = series.quantile([0.25, 0.75])
    IQR = Q3 - Q1
    return Q1 - 1.5 * IQR, Q3 + 1.5 * IQR

# 5. Impute — fit on TRAIN only
num_imputer  = SimpleImputer(strategy='median')    # or 'mean' for Gaussian
cat_imputer  = SimpleImputer(strategy='most_frequent')
knn_imputer  = KNNImputer(n_neighbors=5)           # for multivariate patterns

# 6. Scale — fit on TRAIN only, transform both
scaler = StandardScaler()     # default
# scaler = MinMaxScaler()     # for bounded features / bounded activations
X_train_scaled = scaler.fit_transform(X_train)
X_test_scaled  = scaler.transform(X_test)       # transform only — NEVER fit on test

# 7. Encode — fit on TRAIN only
ohe = OneHotEncoder(sparse_output=False, handle_unknown='ignore', drop='first')
ord_enc = OrdinalEncoder(categories=[['Small','Medium','Large']])

# 8. Imbalance — apply to TRAIN only, never to test
sm = SMOTE(random_state=42)
X_res, y_res = sm.fit_resample(X_train_scaled, y_train)

# 9. Transform (outlier-robust) — fit on TRAIN only
pt = PowerTransformer(method='yeo-johnson')
X_transformed = pt.fit_transform(X_train[skewed_cols])

# 10. Cross-validation — only on the training set
from sklearn.model_selection import StratifiedKFold, cross_val_score
skf = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)
scores = cross_val_score(model, X_res, y_res, cv=skf, scoring='f1')
print(f"F1: {scores.mean():.3f} ± {scores.std():.3f}")  # report as μ ± σ, §17.4

# 11. Final, single test-set evaluation — only after all tuning is finished
test_score = model.fit(X_res, y_res).score(X_test_scaled, y_test)
```

---

*This document covers Steps 1–20 of the course pipeline (general overview through interpretability). Sections marked [inference — verify in class] fill genuine gaps in the lecture notes with standard ML theory and should be checked against course material, not treated as authoritative. Update this document as remaining lecture content (statistical testing depth, error analysis depth, interpretability depth) is taught in full.*

