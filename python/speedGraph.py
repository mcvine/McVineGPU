import numpy as np
from matplotlib import pyplot as plt

x = np.array([1e6, 3e6, 6e6, 1e7, 3e7, 6e7, 1e8])
cputimes = np.array([50.0, 147.0, 293.0, 491.0, 1473.0, 3005.0, 4977.0])
#gputimes = np.array([3.678725, 4.368812, 4.8381, 7.910193, 25.655962])
gputimes = np.array([3.72244, 4.24126, 4.71751, 5.69286, 8.8244, 14.7054, 21.627])
cpuspeed = x / cputimes
gpuspeed = x / gputimes

fig, ax1 = plt.subplots()
ax2 = ax1.twinx()

ax1.plot(x, gpuspeed, ".-", color="#74B71B")
ax1.set_xlabel("Number of Neutrons")
ax1.set_xscale("log")
ax1.set_ylabel("McVineGPU Computation Speed (Number of Neutrons / s)", color="#74B71B")
ax1.set_ylim(0)
ax1.tick_params("y", colors="#74B71B")

ax2.plot(x, cpuspeed, ".-", color="#0000FF")
ax2.set_ylabel("MCViNE Computation Speed (Number of Neutrons / s)", color="#0000FF")
ax2.set_ylim(0, 50000)
ax2.tick_params("y", colors="#0000FF")

fig.suptitle("Speed Comparison of MCViNE vs McVineGPU", y=0.95)

#plt.plot(x, cpuspeed, ".-", color="#0000FF", label="MCViNE")
#plt.plot(x, gpuspeed, ".-", color="#74B71B", label="McVineGPU")

#plt.legend()

#plt.xscale("log")
#plt.yscale("log")

#plt.title("Speed Comparison of MCViNE vs McVineGPU")
#plt.xlabel("Number of Neutrons")
#plt.ylabel("Computation Speed (Number of Neutrons / s)")

#plt.grid()

plt.show()
