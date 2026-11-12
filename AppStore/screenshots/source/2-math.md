# Orbital mechanics, briefly

A satellite in a circular orbit of radius $r$ around a body of mass $M$ moves at speed $v = \sqrt{GM/r}$, and its period follows from Kepler's third law:

$$
T = 2\pi \sqrt{\frac{a^3}{G M}}
$$

The energy needed to change orbits comes from the **vis-viva equation**:

$$
v^2 = G M \left( \frac{2}{r} - \frac{1}{a} \right)
$$

For a Hohmann transfer between circular orbits $r_1$ and $r_2$, the two burns are

$$
\begin{aligned}
\Delta v_1 &= \sqrt{\frac{GM}{r_1}} \left( \sqrt{\frac{2 r_2}{r_1 + r_2}} - 1 \right) \\
\Delta v_2 &= \sqrt{\frac{GM}{r_2}} \left( 1 - \sqrt{\frac{2 r_1}{r_1 + r_2}} \right)
\end{aligned}
$$

| Orbit | Altitude | Period |
|:--|--:|--:|
| Low Earth | 400 km | $\approx 92$ min |
| Geostationary | 35 786 km | $23^\text{h}56^\text{m}$ |
