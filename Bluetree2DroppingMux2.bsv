package Bluetree2DroppingMux2;

export mkBluetree2DroppingMux2;

import Bluetree2::*;
import DReg::*;
import GetPut::*;
import Connectable::*;
import ClientServer::*;
import FIFO::*;
import FIFOF::*;

module mkBluetree2DroppingMux2(IfcBluetree2Mux2#(client_pkt, server_pkt))
    provisos(BluetreePriorityOrdering#(client_pkt, client_prio),
             BluetreeRoutable#(client_pkt, client_cpu_id),
             BluetreeRoutable#(server_pkt, server_cpu_id),
             PrimSelectable#(client_cpu_id, client_cpu_id_bit),
             PrimSelectable#(server_cpu_id, server_cpu_id_bit),
             Literal#(client_cpu_id_bit),
             Literal#(server_cpu_id_bit),
             Bits#(client_pkt, client_pkt_bits),
             Bits#(server_pkt, server_pkt_bits),
             Eq#(server_cpu_id_bit),
             Literal#(client_cpu_id),
             Literal#(server_cpu_id)
    );

    Reg#(server_pkt) down    <- mkDReg(unpack(0));
    Reg#(Bool) canRelayDown0 <- mkDReg(False);
    Reg#(Bool) canRelayDown1 <- mkDReg(False);

    Reg#(Maybe#(client_pkt)) up <- mkDReg(tagged Invalid);
    RWire#(client_pkt) in0      <- mkRWire();
    RWire#(client_pkt) in1      <- mkRWire();

    // Handle input routing
    rule routeUp;
        if(in0.wget matches tagged Valid .up0) begin
            if(in1.wget matches tagged Valid .up1) begin
                // Both are valid. Do selection
                client_prio p0 = getCpuPrio(up0);
                client_prio p1 = getCpuPrio(up1);

                if(p0 <= p1)
                    up <= tagged Valid up0;
                else
                    up <= tagged Valid up1;
            end
            else begin
                // Only up0 is valid. Route unconditionally.
                up <= tagged Valid up0;
            end
        end
        else if(in1.wget matches tagged Valid .up1) begin
            // Only up1 is valid. Route unconditionally.
            up <= tagged Valid up1;
        end
    endrule

    interface Client client;
        interface Get request;
            method ActionValue#(client_pkt) get() if(up matches tagged Valid .x);
                return x;
            endmethod
        endinterface

        interface Put response;
            method Action put(server_pkt pkt);
                server_cpu_id cpu_id = getCpuId(pkt);
                if(cpu_id[0] == 0)
                    canRelayDown0 <= True;
                else
                    canRelayDown1 <= True;

                cpu_id = cpu_id >> 1;
                pkt = setCpuId(pkt, cpu_id);
                down <= pkt;
            endmethod
        endinterface
    endinterface

    interface Server server0;
        interface Put request;
            method Action put(client_pkt pkt);
                // Do the cpu_id setting here, as it saves a mess further up.
                client_cpu_id cpu_id = getCpuId(pkt);
                cpu_id = (cpu_id << 1) | 0;
                pkt = setCpuId(pkt, cpu_id);
                in0.wset(pkt);
            endmethod
        endinterface
        
        interface Get response;
            method ActionValue#(server_pkt) get() if(canRelayDown0);
                return down;
            endmethod
        endinterface
    endinterface

    interface Server server1;
        interface Put request;
            method Action put(client_pkt pkt);
                client_cpu_id cpu_id = getCpuId(pkt);
                cpu_id = (cpu_id << 1) | 1;
                pkt = setCpuId(pkt, cpu_id);
                in1.wset(pkt);
            endmethod
        endinterface

        interface Get response;
            method ActionValue#(server_pkt) get() if(canRelayDown1);
                return down;
            endmethod
        endinterface
    endinterface
endmodule

endpackage