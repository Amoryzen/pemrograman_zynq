`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Timing harness untuk place & route out-of-context (HANYA untuk analisis timing,
// tidak untuk simulasi atau dipakai di block design).
//
// Semua port axis_nn diberi satu register di depan/belakang. Dengan begitu semua
// jalur yang dianalisis adalah register -> register di dalam FPGA, sama seperti
// ketika axis_nn tersambung ke AXI DMA Zynq. Port top-level diberi false path.
// Resource core diambil dari instance "dut" di laporan utilization hierarkis.
//////////////////////////////////////////////////////////////////////////////////
module axis_nn_ooc
    (
        input wire         aclk,
        input wire         aresetn,
        output reg         s_axis_tready,
        input wire [63:0]  s_axis_tdata,
        input wire         s_axis_tvalid,
        input wire         s_axis_tlast,
        input wire         m_axis_tready,
        output reg [63:0]  m_axis_tdata,
        output reg         m_axis_tvalid,
        output reg         m_axis_tlast
    );

    reg        aresetn_r;
    reg [63:0] s_tdata_r;
    reg        s_tvalid_r, s_tlast_r, m_tready_r;

    wire        s_tready_w;
    wire [63:0] m_tdata_w;
    wire        m_tvalid_w, m_tlast_w;

    always @(posedge aclk)
    begin
        aresetn_r     <= aresetn;
        s_tdata_r     <= s_axis_tdata;
        s_tvalid_r    <= s_axis_tvalid;
        s_tlast_r     <= s_axis_tlast;
        m_tready_r    <= m_axis_tready;
        s_axis_tready <= s_tready_w;
        m_axis_tdata  <= m_tdata_w;
        m_axis_tvalid <= m_tvalid_w;
        m_axis_tlast  <= m_tlast_w;
    end

    axis_nn dut
    (
        .aclk(aclk),
        .aresetn(aresetn_r),
        .s_axis_tready(s_tready_w),
        .s_axis_tdata(s_tdata_r),
        .s_axis_tvalid(s_tvalid_r),
        .s_axis_tlast(s_tlast_r),
        .m_axis_tready(m_tready_r),
        .m_axis_tdata(m_tdata_w),
        .m_axis_tvalid(m_tvalid_w),
        .m_axis_tlast(m_tlast_w)
    );

endmodule
