import numpy as np
import matplotlib.pyplot as plt
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch
from matplotlib.text import Text

# Create figure with custom layout
fig = plt.figure(figsize=(14, 10))
fig.patch.set_facecolor('white')

# Title
fig.text(0.5, 0.95, 'Fourier Series: general idea', 
         fontsize=24, weight='bold', ha='center')

# Bullet point 1
fig.text(0.05, 0.88, '•', fontsize=16)
fig.text(0.08, 0.88, 
         'The Fourier Series decomposes functions into a sum of sine and cosine terms with differing\nfrequencies and amplitudes',
         fontsize=12, va='top')

# Bullet point 2
fig.text(0.05, 0.82, '•', fontsize=16)
fig.text(0.08, 0.82, 
         r'The original function $f(t)$, is called the "real space representation" and is continuous',
         fontsize=12, va='top')

# ============= TOP VISUALIZATION =============
# Create axes for the signal decomposition
ax1 = fig.add_axes([0.08, 0.50, 0.25, 0.25])  # Original signal
ax2 = fig.add_axes([0.50, 0.58, 0.20, 0.15])  # Component 1
ax3 = fig.add_axes([0.50, 0.52, 0.20, 0.15])  # Component 2
ax4 = fig.add_axes([0.75, 0.50, 0.20, 0.25])  # Sum result

# Generate signals
t = np.linspace(0, 2, 1000)

# Original complex signal (sum of components)
signal = 2 * np.sin(2 * np.pi * 3 * t) + 5 * np.sin(2 * np.pi * 1 * t)

# Component 1: f=3, A=2
comp1 = 2 * np.sin(2 * np.pi * 3 * t)

# Component 2: f=1, A=5
comp2 = 5 * np.sin(2 * np.pi * 1 * t)

# Plot original signal
ax1.plot(t, signal, 'r-', linewidth=2)
ax1.set_ylim(-8, 8)
ax1.set_xlim(0, 2)
ax1.set_title('$f(t)$', fontsize=14, weight='bold')
ax1.text(1, -10, 'Original signal (function)', ha='center', fontsize=10, 
         color='red', weight='bold')
ax1.set_xticks([])
ax1.set_yticks([])
ax1.spines['top'].set_visible(False)
ax1.spines['right'].set_visible(False)

# Plot component 1
ax2.plot(t, comp1, 'b-', linewidth=1.5)
ax2.set_ylim(-8, 8)
ax2.set_xlim(0, 2)
ax2.text(1, -10, r'$2\sin(2\pi(3)x)$ $A=2$ $f=3$', ha='center', fontsize=9)
ax2.set_xticks([])
ax2.set_yticks([])
ax2.spines['top'].set_visible(False)
ax2.spines['right'].set_visible(False)

# Plot component 2
ax3.plot(t, comp2, 'lightblue', linewidth=1.5)
ax3.set_ylim(-8, 8)
ax3.set_xlim(0, 2)
ax3.text(1, -10, r'$5\sin(2\pi(1)x)$ $A=5$ $f=1$', ha='center', fontsize=9)
ax3.set_xticks([])
ax3.set_yticks([])
ax3.spines['top'].set_visible(False)
ax3.spines['right'].set_visible(False)

# Plot sum (same as original)
ax4.plot(t, signal, color='lightgreen', linewidth=2)
ax4.set_ylim(-8, 8)
ax4.set_xlim(0, 2)
ax4.set_xticks([])
ax4.set_yticks([])
ax4.spines['top'].set_visible(False)
ax4.spines['right'].set_visible(False)

# Add arrows and labels
# Arrow from original to decomposition
fig.text(0.37, 0.65, 'Spectral\n═══\nDecomposition:', 
         ha='center', fontsize=10, weight='bold', color='blue',
         bbox=dict(boxstyle='round,pad=0.5', facecolor='lightblue', alpha=0.3))

# Plus sign
fig.text(0.48, 0.62, '+', fontsize=30, weight='bold', ha='center')

# Equals/arrow to result
fig.text(0.73, 0.62, '→', fontsize=30, weight='bold', ha='center')

# ============= MIDDLE SECTION =============
# Bullet point 3
fig.text(0.05, 0.45, '•', fontsize=16)
fig.text(0.08, 0.45, 
         r'The transformed function $F(\omega)$, is called the "frequency representation" and is discrete',
         fontsize=12, va='top')

# ============= BOTTOM VISUALIZATION =============
# Create axes for frequency domain
ax5 = fig.add_axes([0.15, 0.15, 0.70, 0.25])

# Draw the stem plot for frequency domain
frequencies = [1, 3]
amplitudes = [5, 2]

# Draw stems
for f, a in zip(frequencies, amplitudes):
    ax5.plot([f, f], [0, a], 'b-', linewidth=3)
    ax5.plot(f, a, 'bo', markersize=10)
    # Add arrow head
    ax5.annotate('', xy=(f, a), xytext=(f, a-0.3),
                arrowprops=dict(arrowstyle='->', color='blue', lw=2))

# Labels
ax5.text(1, 5.5, '5', ha='center', fontsize=11, weight='bold')
ax5.text(3, 2.5, '2', ha='center', fontsize=11, weight='bold')

# Axis labels
ax5.set_xlabel('frequency space', fontsize=12, weight='bold')
ax5.set_ylabel('$A(f)$', fontsize=14, rotation=0, labelpad=20)
ax5.text(0.5, 6, 'frequency\nspace\ndiscrete', fontsize=10, 
         style='italic', color='gray')

# Set axis properties
ax5.set_xlim(0, 4)
ax5.set_ylim(0, 6)
ax5.set_xticks([1, 3])
ax5.set_xticklabels(['1', '3'])
ax5.spines['top'].set_visible(False)
ax5.spines['right'].set_visible(False)
ax5.grid(True, alpha=0.3, linestyle='--')

# Add formula annotations
fig.text(0.15, 0.35, r'$F(f) = A(f) \rightarrow (f_n, A_n) \in [(1,5), (3,2)]$', 
         fontsize=12, weight='bold')
fig.text(0.15, 0.31, 'forms a new function: amplitude as a function of frequency',
         fontsize=10, style='italic', color='blue')
fig.text(0.15, 0.28, r'$\omega = 2\pi f$', fontsize=11)

# Bullet point 4
fig.text(0.05, 0.08, '•', fontsize=16)
fig.text(0.08, 0.08, 
         r'The inverse transform re-construct $f(t)$ from $F(\omega)$ given amplitudes & frequencies',
         fontsize=12, va='top')

plt.savefig('/home/ben/dsan-6500-2026/lectures/week-3/fourier_series_slide.png', 
            dpi=300, bbox_inches='tight', facecolor='white')
plt.show()

print("Slide saved to: /home/ben/dsan-6500-2026/lectures/week-3/fourier_series_slide.png")
