This tool measures the IOPS and bandwidth from an upstairs to a set of three
downstairs. It accepts the usual set of Crucible arguments:

    cargo run --release -p measure-iops -- \
        -t 127.0.0.1:44101 \
        -t 127.0.0.1:44102 \
        -t 127.0.0.1:44103 \
        --key "$(openssl rand -base64 32)"

Output will show some statistics related to the run:

    IOPS: [1060.5188, 535.55096, 342.29413, 266.0666, 975.55774, 581.5098, 368.57507, 277.63745, 210.09323, 997.99286, 564.8316, 370.5759, 281.1167, 214.91843, 1022.8198, 576.4766, 370.70322, 266.79498, 204.88252, 1049.1289, 521.58124, 326.27725, 231.60463, 250.97418, 1206.1144, 495.56763, 311.36276, 256.4053, 301.95493, 1284.1713, 411.6274, 320.6126, 228.9134, 198.15662, 1222.0442, 489.95615, 303.24838, 255.41228, 318.83762, 1215.2572, 432.60532, 306.87247, 228.31776, 336.62692, 1181.6915, 436.94943, 305.37833, 243.4393, 361.98187, 1170.3591, 411.28217, 297.5957, 227.53906, 375.8531, 1110.321, 428.7218, 301.49493, 269.94434, 402.8902, 1144.8269, 383.7488, 284.26498, 252.16966, 403.8011, 1078.9503, 438.96133, 312.3859, 260.41327, 429.90765, 1150.9951, 430.98767, 299.80392, 229.90257, 299.97418, 1186.887, 427.21585, 297.108, 220.93596, 464.9715, 1053.9406, 434.46204, 296.8956, 248.68004, 441.9947, 971.58954, 465.7012, 310.55557, 259.9112, 463.90683, 963.07007, 482.0798, 296.60132, 259.49713, 452.9664, 1023.61053, 414.3616, 312.71567, 240.88193, 506.94513, 1089.1649]
    IOPS mean 505.05734 stddev 324.76517
    IOPS min 198.15662 max 1284.1713

    BW: [4343885.0, 2193616.8, 1402036.8, 1089808.8, 3995884.5, 2381864.3, 1509683.5, 1137203.0, 860541.9, 4087778.8, 2313550.3, 1517878.9, 1151454.0, 880305.9, 4189470.0, 2361248.3, 1518400.4, 1092792.3, 839198.8, 4297232.0, 2136396.8, 1336431.6, 948652.56, 1027990.25, 4940244.5, 2029845.0, 1275341.9, 1050236.1, 1236807.4, 5259965.5, 1686025.9, 1313229.3, 937629.3, 811649.5, 5005493.0, 2006860.4, 1242105.4, 1046168.7, 1305958.9, 4977693.5, 1771951.4, 1256949.6, 935189.56, 1378823.9, 4840208.5, 1789744.9, 1250829.6, 997127.4, 1482677.8, 4793791.0, 1684611.8, 1218952.0, 932000.0, 1539494.3, 4547875.0, 1756044.5, 1234923.3, 1105692.0, 1650238.3, 4689211.0, 1571835.1, 1164349.4, 1032886.94, 1653969.3, 4419380.5, 1797985.6, 1279532.6, 1066652.8, 1760901.8, 4714476.0, 1765325.5, 1227996.9, 941680.94, 1228694.3, 4861489.0, 1749876.1, 1216954.4, 904953.7, 1904523.3, 4316940.5, 1779556.5, 1216084.4, 1018593.44, 1810410.3, 3979630.8, 1907512.1, 1272035.6, 1064596.3, 1900162.4, 3944735.0, 1974598.9, 1214879.0, 1062900.3, 1855350.4, 4192708.8, 1697225.1, 1280883.4, 986652.4, 2076447.3, 4461219.5]
    BW mean 2068714.9 stddev 1330238.1
    BW min 811649.5 max 5259965.5

Each measurement is shown in an unsorted list so changes over time can be
observed, along with mean, stddev, min, and max.

For Crucible, one IOP is measured as 16384 bytes. Crucible will round up to
this:

- if you send one 1024 byte request, that counts as one IOP.
- if you send one 16000 byte request, that counts as one IOP.
- if you send one 16384 + 1, that counts as two IOPs.

Tool arguments:

    --samples
        how many samples to take (default 100). also the number of seconds the tool runs.

    --iop-limit
        how many IOPs per second to set

    --io-size-in-bytes
        how large of a read or write operation to send. defaults to block size.

    --io-depth
        how many IOs to send at a time

    --bw-limit-in-bytes
        how many bytes per second to set
