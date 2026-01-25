# Simulation Result
<img width="1436" height="818" alt="image" src="https://github.com/user-attachments/assets/85a7b722-adcf-406c-9935-e53bc6a4cd1d" />

Simulation ensured that the previous timing constrains has been satisfied.
The next tables shows the actual timings from the simulation against the required ones specified in the TRM

### ADC – Universal Actual Timing

| Parameter | Min | Typ | Max | Unit | Description | Actual Time (In Design) | Case | Unit |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **t_CYCLE** | 1 | – | – | µs | Minimum time between consecutive CONVST rising edges (excluding burst and oversampling modes) | 3120 | Min | ns |
| **t_CONV_LOW** | 50 | – | – | ns | CONVST low pulse width | 3120 | Min | ns |
| **t_CONV_HIGH** | 50 | – | – | ns | CONVST high pulse width | 60 | - | ns |
| **t_BUSY_DELAY** | – | – | 32 | ns | CONVST high to BUSY high (manual mode) | We wait for 70 ns before if isn't yet High -> reset | - | - |
| **t_CS_SETUP** | 20 | – | – | ns | BUSY falling edge to CS falling edge setup time | 70 | - | ns |
| **t_CH_SETUP** | 50 | – | – | ns | Channel select setup time in hardware mode for CHSELx | Not Required/Used | - | - |
| **t_CH_HOLD** | 20 | – | – | ns | Channel select hold time in hardware mode for CHSELx | Not Required/Used | - | - |
| **t_CONV** | – | 475 | 520 | ns | Conversion time for the selected channel pair | Not required, managed by the HW in the burst mode | - | - |
| **t_ACQ** | – | 480 | – | ns | Acquisition time for the selected channel pair | Not required, managed by the HW in the burst mode | - | - |
| **t_QUIET** | 50 | – | – | ns | CS rising edge to next CONVST rising edge | 60 | - | ns |
| **t_RESET_LOW (Partial Reset)** | 40 | – | 500 | ns | Partial RESET low pulse width | Not Required/Used | - | - |
| **t_RESET_LOW (Full Reset)** | 1.2 | – | – | µs | Full RESET low pulse width | 1490 | - | ns |
| **t_DEVICE_SETUP (Partial Reset)** | 50 | – | – | ns | Time between partial RESET high and CONVST rising edge | Not Required/Used | - | - |
| **t_DEVICE_SETUP (Full Reset)** | 15 | – | – | ms | Time between full RESET high and CONVST rising edge | 20 | - | ms |
| **t_WRITE (Partial Reset)** | 50 | – | – | ns | Time between partial RESET high and CS for write operation | Not Required/Used | - | - |
| **t_WRITE (Full Reset)** | 240 | – | – | µs | Time between full RESET high and CS for write operation | Not Required/Used | - | - |
| **t_RESET_WAIT** | 1 | – | – | ms | Time between stable VCC/VDRIVE and release of RESET (see Figure 50) | Included in the set up wait as we waiting for 20 ms | - | - |
| **t_RESET_SETUP (Partial Reset)** | 10 | – | – | ns | Time prior to release of RESET that queried hardware inputs must be stable | Not Required/Used | - | - |
| **t_RESET_SETUP (Full Reset)** | 0.05 | – | – | ms | Time prior to release of RESET that queried hardware inputs must be stable | Not Required/Used | - | - |
| **t_RESET_HOLD (Partial Reset)** | 10 | – | – | ns | Time after release of RESET that queried hardware inputs must be stable | Not Required/Used | - | - |
| **t_RESET_HOLD (Full Reset)** | 0.24 | – | – | ms | Time after release of RESET that queried hardware inputs must be stable | Not Required/Used | - | - |

