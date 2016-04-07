package TUEBenchmark;

import TestUtils::*;
import GetPut::*;
import Connectable::*;
import ClientServer::*;
import StmtFSM::*;
import Vector::*;
import Assert::*;
import Bluetree2::*;
import Bluetree2DroppingMux2::*;
import BluetreeRateLimiterRoot2::*;
import TueGenericArbiter2::*;
import BluetreeTrafficGenerators2::*;

`define MUX_LEVELS 4
`define MUX_DEGREE 2
`define NGENS      16      // This MUST be equal to MUX_DEGREE ** MUX_LEVELS.
`define ACTIVE_PERIOD 99

// Data types etc
typedef Bit#(32) MyDataReg;
typedef Bit#(5)  MyPrio;

typedef struct {
    BluetreeClientMessageType   message_type;
    MyDataReg                   data;
    BluetreeBEN                 ben;
    BluetreeBlockAddress        address;
    BluetreeTaskId              task_id;
    BluetreeCPUId               cpu_id;
    MyPrio                      prio;
    BluetreeBurstCounter        size;
} BluetreeTestClientPacket deriving (Bits, Eq);

typedef struct {
    BluetreeMessageType     message_type;
    MyDataReg               data;
    BluetreeBlockAddress    address;
    BluetreeTaskId          task_id;
    BluetreeCPUId           cpu_id;
} BluetreeTestServerPacket deriving (Bits, Eq);

instance BluetreeDataContainer#(BluetreeTestClientPacket, MyDataReg);
    function MyDataReg getData(BluetreeTestClientPacket x);
	return x.data;
    endfunction
    
    function BluetreeTestClientPacket setData(BluetreeTestClientPacket x, MyDataReg d);
	x.data = d;
	return x;
    endfunction
endinstance

instance BluetreeDataContainer#(BluetreeTestServerPacket, MyDataReg);
    function MyDataReg getData(BluetreeTestServerPacket x);
	return x.data;
    endfunction
    
    function BluetreeTestServerPacket setData(BluetreeTestServerPacket x, MyDataReg d);
	x.data = d;
	return x;
    endfunction
endinstance

instance BluetreeServerType#(BluetreeTestServerPacket);
    function BluetreeMessageType getMessageType(BluetreeTestServerPacket x);
        return x.message_type;
    endfunction

    function BluetreeTestServerPacket setMessageType(BluetreeTestServerPacket x, BluetreeMessageType t);
        x.message_type = t;
        return x;
    endfunction
endinstance

instance BluetreeClientType#(BluetreeTestClientPacket);
    function BluetreeClientMessageType getClientMessageType(BluetreeTestClientPacket x);
        return x.message_type;
    endfunction

    function BluetreeTestClientPacket setClientMessageType(BluetreeTestClientPacket x, BluetreeClientMessageType t);
        x.message_type = t;
        return x;
    endfunction
endinstance

instance BluetreeRoutable#(BluetreeTestClientPacket, BluetreeCPUId);
    function BluetreeCPUId getCpuId(BluetreeTestClientPacket x);
        return x.cpu_id;
    endfunction

    function BluetreeTestClientPacket setCpuId(BluetreeTestClientPacket x, BluetreeCPUId cpu_id);
        x.cpu_id = cpu_id;
        return x;
    endfunction
endinstance

instance BluetreeRoutable#(BluetreeTestServerPacket, BluetreeCPUId);
    function BluetreeCPUId getCpuId(BluetreeTestServerPacket x);
        return x.cpu_id;
    endfunction

    function BluetreeTestServerPacket setCpuId(BluetreeTestServerPacket x, BluetreeCPUId cpu_id);
        x.cpu_id = cpu_id;
        return x;
    endfunction
endinstance

instance BluetreePriorityOrdering#(BluetreeTestClientPacket, MyPrio);
    function MyPrio getCpuPrio(BluetreeTestClientPacket x);
        return x.prio;
    endfunction

    function BluetreeTestClientPacket setCpuPrio(BluetreeTestClientPacket pkt, MyPrio prio);
        pkt.prio = prio;
        return pkt;
    endfunction
endinstance

(* synthesize *)
module mkTUEBenchmark(Empty);
    Integer i = 0;
    Integer j = 0;

    // Annoyingly, we need this. This is because the "num" argument to a Vector instantiation must be static.
    // This can be from a T*#() declaration, but not from an integer statement or arithmetic. For this reason,
    // we need to manually specify the number of traffic generators. We check here to make sure that the programmer
    // has correctly specified the relation between these three constants.
    staticAssert(`MUX_DEGREE**`MUX_LEVELS == `NGENS, "NGENS *MUST* be equal to MUX_LEVELS ** MUX_DEGREE");

    // This is a hack (obviously). Make a list with the first index being the level ID, and the next the mux within
    // that level. Of course, there will be storage for more muxes, but they won't all be instantiated. Accessing
    // and invalid one will be caught by Bluespec's analysis.
    IfcBluetree2Mux2#(BluetreeTestClientPacket, BluetreeTestServerPacket) muxLevels[`MUX_LEVELS][`NGENS];


    Vector#(`NGENS, BluetreeTrafficGenerator2#(BluetreeTestClientPacket, BluetreeTestServerPacket)) trafficGens;
    Vector#(`NGENS, TueGenericArbiter2#(BluetreeTestClientPacket, BluetreeTestServerPacket)) limiters;
    Server#(BluetreeTestClientPacket, BluetreeTestServerPacket) mem <- mkMemConsumer2(0);
    BluetreeRateLimiterRoot2#(BluetreeTestClientPacket, BluetreeTestServerPacket) root <- mkBluetreeRateLimiterRoot2();

    // Actually create all of the muxes.
    for(i = 0; i < `MUX_LEVELS; i = i + 1) begin
        for(j = 0; j < `MUX_DEGREE**i; j = j + 1) begin
            muxLevels[i][j] <- mkBluetree2DroppingMux2();
        end
    end
    
    for(i = 0; i < `NGENS; i = i + 1) begin
	trafficGens[i] <- mkBluetreeRandomTrafficGenerator2(1650, 3000);
	
	
	if(i < 8)
	    limiters[i] <- mkTueGenericArbiter2(0, 0, 0, 1, 0, fromInteger(i), 0, fromInteger(i), fromInteger(i), 100, 16); // TDM
	else
	    limiters[i] <- mkTueGenericArbiter2(1, 1, 1, 0, 1, fromInteger(i), fromInteger(i + `NGENS), 4, 1, 100, 16); // FBSP
	    //limiters[i] <- mkTueGenericArbiter2(16, 16, 0, 1, 16, fromInteger(i), fromInteger(i+`NGENS), 100, 15, 100, 0); // CCSP
	    //limiters[i] <- mkTueGenericArbiter2(1, 1, 1, 0, 1, fromInteger(i), fromInteger(i+`NGENS), 4, 1, 100, 16); // FBSP
    end
    
    // Now connect
    for(i = 0; i < (`MUX_LEVELS - 1); i = i + 1) begin
        for(j = 0; j < `MUX_DEGREE**(i+1); j = j + `MUX_DEGREE) begin
            mkConnection(muxLevels[i][j/`MUX_DEGREE].server0, muxLevels[i+1][j+0].client);
            mkConnection(muxLevels[i][j/`MUX_DEGREE].server1, muxLevels[i+1][j+1].client);
        end
    end

    // And connect to the gens
    for(i = 0; i < `NGENS; i = i + `MUX_DEGREE) begin
        mkConnection(limiters[i+0].server, trafficGens[i+0].client);
        mkConnection(limiters[i+1].server, trafficGens[i+1].client);
        mkConnection(muxLevels[`MUX_LEVELS-1][i/`MUX_DEGREE].server0, limiters[i+0].client);
        mkConnection(muxLevels[`MUX_LEVELS-1][i/`MUX_DEGREE].server1, limiters[i+1].client);
    end

    mkConnection(muxLevels[0][0].client, root.server);
    mkConnection(root.client, mem);
endmodule
endpackage