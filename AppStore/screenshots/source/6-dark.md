# Trailhead Weather Station

A solar-powered station that logs temperature, wind and rain at the trailhead and posts readings every ten minutes.

> [!TIP]
> Readings are cached on the device, so a dropped connection never loses data.

| Sensor | Reading | Updated |
|:--|--:|:--|
| Temperature | 18.4 °C | 2 min ago |
| Wind | 12 km/h NW | 2 min ago |
| Rain (24 h) | 3.2 mm | 9 min ago |

## Roadmap

- [x] Weatherproof enclosure and solar charging
- [ ] Snow depth sensor :snowflake:

```python
def dew_point(temp_c: float, humidity: float) -> float:
    """Magnus approximation of the dew point in °C."""
    a, b = 17.62, 243.12
    gamma = (a * temp_c) / (b + temp_c) + math.log(humidity / 100)
    return (b * gamma) / (a - gamma)
```
