

module decompose (
    input  wire [45:0] r,
    input  wire        gamma_sel,
    output wire [5:0]  r1,
    output wire [18:0] r0
);

    localparam [22:0] Q        = 23'd8380417;
    localparam [22:0] Q_MINUS1 = 23'd8380416;

    // γ₂ = 95232: mod=190464, m=5772805
    localparam [17:0] MOD_G0    = 18'd190464;
    localparam [22:0] M_G0      = 23'd5772805;
    localparam [16:0] GAMMA2_G0 = 17'd95232;

    // γ₂ = 261888: mod=523776, m=2099202
    localparam [18:0] MOD_G1    = 19'd523776;
    localparam [21:0] M_G1      = 22'd2099202;
    localparam [17:0] GAMMA2_G1 = 18'd261888;

    // STAGE 1: PSEUDO-MERSENNE mod q
    //
    // Identity: 2^23 ≡ 2^13 - 1 (mod q)
    // Reduction: t_low + (t_high << 13) - t_high  (no multiplier)
    //
    // Pass 1: 46-bit → 36-bit  (t1 max = 68,719,468,544)
    // Pass 2: 36-bit → 27-bit  (t2 max = 75,481,088)
    // Pass 3: 27-bit → 24-bit  (t3 max = 8,454,135 < 2Q)
    // Final : conditional subtract → t in [0, Q-1]
  

    // ----- Pass 1 -----
    wire [22:0] rh1 = r[45:23];
    wire [22:0] rl1 = r[22:0];
    wire [35:0] t1  = {13'b0, rl1} + {rh1, 13'b0} - {13'b0, rh1};

    // ----- Pass 2 -----
    wire [12:0] rh2 = t1[35:23];
    wire [22:0] rl2 = t1[22:0];
    wire [26:0] t2  = {4'b0, rl2} + {rh2, 13'b0} - {14'b0, rh2};

    // ----- Pass 3 -----
    wire [3:0]  rh3 = t2[26:23];
    wire [22:0] rl3 = t2[22:0];
    wire [23:0] t3  = {1'b0, rl3} + {7'b0, rh3, 13'b0} - {20'b0, rh3};

    // ----- Final conditional subtract -----
    wire [22:0] t = (t3 >= {1'b0, Q}) ? (t3[22:0] - Q) : t3[22:0];
    // t guaranteed in [0, Q-1]

    // STAGE 2: BARRETT REDUCTION mod 2γ₂
    //
    // Replace division t/2γ₂ with multiply-shift using precomputed reciprocal:
    //   m     = floor(2^40 / 2γ₂)          precomputed constant
    //   q_est = floor(t * m / 2^40)         approximate quotient = t >> 40
    //   r0    = t - q_est * 2γ₂             approximate remainder
    //
    // Barrett correction (at most once):
    //   if r0 >= 2γ₂: r0 -= 2γ₂, q_est += 1
    //   (fires when floor rounding in m caused q_est to be 1 too small)
    //
    // Centering correction (mod±):
    //   if r0 > γ₂: r0 -= 2γ₂, q_est += 1
    //   (centers r0 from [0, 2γ₂) into (-γ₂, γ₂])
    //
    // q_est after both corrections = r1 (no second divider needed)
  

    // ----- Select constants based on gamma_sel -----
    wire [18:0] dec_mod    = gamma_sel ? {1'b0, MOD_G1}    : {1'b0, MOD_G0};
    wire [22:0] dec_m      = gamma_sel ? {1'b0, M_G1}      :        M_G0;
    wire [18:0] dec_gamma2 = gamma_sel ? {2'b0, GAMMA2_G1} : {2'b0, GAMMA2_G0};

    // ----- Barrett: approximate quotient -----
    // t is 23-bit, m is 23-bit → product is 46-bit (max = 48,378,507,386,880 < 2^46)
    wire [45:0] dec_prod  = {23'b0, t} * {23'b0, dec_m}; // i will keep it t * m to be more clear, but it is the same as {23'b0, t} * {23'b0, dec_m}
    wire [5:0]  dec_qest0 = dec_prod[45:40];   // >> 40, 6-bit, max = 43

    // ----- Barrett: approximate remainder -----
    // q_est * mod: 6-bit * 19-bit = 25-bit (max = 43*523776 = 22,522,368 < 2^25)
    wire [24:0] dec_qmod0 = {19'b0, dec_qest0} * dec_mod;
    wire [22:0] dec_r0b0  = t - dec_qmod0[22:0]; // true remainder fits in 23 bits since t < q < 2γ₂ , top bits of qmod0 are irrelevant as they go outside of the range of t

    // ----- Barrett correction -----
    // Fires when q_est was 1 too small (floor rounding in m)
    wire        dec_bcorr = (dec_r0b0 >= {4'b0, dec_mod[18:0]});
    wire [5:0]  dec_qest1 = dec_bcorr ? (dec_qest0 + 6'd1) : dec_qest0;
    wire [18:0] dec_r0b1  = dec_bcorr ? (dec_r0b0[18:0] - dec_mod)
                                       :  dec_r0b0[18:0];
    // dec_r0b1 now in [0, 2γ₂ - 1] which is at max 19 bits so we can safely take the bottom 19 bits

    // ----- Centering correction -----
    // Fires when r0b1 > γ₂ — subtracts 2γ₂ to move r0 to negative side
    // After: dec_r0c is 19-bit two's complement in (-γ₂, γ₂]
    wire        dec_ccorr = (dec_r0b1 > dec_gamma2);
    wire [5:0]  dec_qest2 = dec_ccorr ? (dec_qest1 + 6'd1) : dec_qest1;
    wire [18:0] dec_r0c   = dec_ccorr ? (dec_r0b1 - dec_mod) : dec_r0b1;
    // dec_r0c[18] is the sign bit


    //  DILITHIUM EDGE CASE CHECK
    // Fires for the top γ₂ values of t:
    //   γ₂=95232:  t ∈ [8,285,185, 8,380,416]  (95,232 values)
    //   γ₂=261888: t ∈ [8,118,529, 8,380,416] (261,888 values)
    //
    // Correction:
    //   r1 = 0        
    //   r0 = r0 - 1   

    // Compute t - r0c carefully (r0c may be negative two's complement)
    wire        dec_r0_neg = dec_r0c[18];              // sign bit of r0c
    wire [17:0] dec_r0_abs = dec_r0_neg
                              ? (~dec_r0c[17:0] + 18'd1)  // two's complement abs
                              :   dec_r0c[17:0];

    // t - r0c:
    //   r0c >= 0: diff = t - r0c
    //   r0c <  0: diff = t + |r0c|   (subtracting a negative = adding positive)
    wire [22:0] dec_diff = dec_r0_neg
                            ? (t + {5'b0, dec_r0_abs})
                            : (t - {5'b0, dec_r0c[17:0]});

    wire dec_edge = (dec_diff == Q_MINUS1);

    // ----- Final outputs -----
    assign r1 = dec_edge ? 6'd0              : dec_qest2;
    assign r0 = dec_edge ? (dec_r0c - 19'd1) : dec_r0c;

endmodule