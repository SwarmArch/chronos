<project xmlns="com.autoesl.autopilot.project" name="astar_prj" top="astar_dist">
    <includePaths/>
    <libraryPaths/>
    <libraryFlag/>
    <Simulation argv="">
        <SimFlow askAgain="false" name="csim" ldflags="-std=c++0x" csimMode="0" lastCsimMode="0" compiler="true"/>
    </Simulation>
    <files xmlns="">
        <file name="../../../../../../../../../ordspec-benchmarks/inputs/astar/north-america.bin" sc="0" tb="1" cflags="  -Wno-unknown-pragmas"/>
        <file name="../../monaco.bin" sc="0" tb="1" cflags="  -Wno-unknown-pragmas"/>
        <file name="../../massachusetts.bin" sc="0" tb="1" cflags="  -Wno-unknown-pragmas"/>
        <file name="../../germany.bin" sc="0" tb="1" cflags="  -Wno-unknown-pragmas"/>
        <file name="../../astar_test.cpp" sc="0" tb="1" cflags="  -Wno-unknown-pragmas"/>
        <file name="astar.cpp" sc="0" tb="false" cflags=""/>
    </files>
    <solutions xmlns="">
        <solution name="solution1" status="active"/>
        <solution name="solution1" status="active"/>
    </solutions>
</project>

