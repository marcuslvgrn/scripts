#! /bin/sh
# /etc/init.d/ramdisk.sh
#written by christian geiler

f_error()
{
    echo "Usage: /etc/init.d/ramdisk.sh {start|stop|sync}"
    exit 1
}

f_get_user_answer_yes_no() 
{
    local isAnswerCorrect="false"
    while [ "$isAnswerCorrect" != "true" ];
    do
        echo " * [yes|no]? " 1>&2
        local answer="yes"

        # read -t <timeout> # posix style
        STTY=`stty -g`
        stty -icanon 
        stty min 0 time 50
        stty_answer=`dd count=3 bs=1 2>/dev/null`
        stty $STTY 

        if [ -n "$stty_answer" ];
        then
          local answer=$stty_answer
        fi
        
        if [ "yes" = "`echo $answer | grep "yes"`" ];
        then
          local isAnswerCorrect="true"
        else
            if [ "no" = "`echo $answer | grep "no"`" ];
            then  
                local isAnswerCorrect="true"
            fi
        fi
    done
    echo "$answer"
}

f_getOctalFileRights()
{
    local file_name=$1
    echo "$( stat --format=%a $file_name;  )"
}

f_getUsernameOfOwnerOfFile()
{
    local file_owner=$1
    echo "$( stat --format=%U $file_owner; )"
}

f_getGroupnameOfFile()
{
    local file_group=$1
    echo "$( stat --format=%G $file_group; )"
}

f_update_squashfs()
{
    #Funktions parameter
    local directory=$1                                              #directory on HDD which should be loaded into RAM
    
    #locale variablen
    local hiddenPD="/.physical_disk"
    local directoryPD="$hiddenPD""$directory"                       #directory on HDD which is a mountpoint for HDD disk
    local squashfs_file_name="`basename "$directory"".squashfs"`"
    local directoryRights=`f_getOctalFileRights "$directory"`      #rights of directory
    local directoryOwner=`f_getUsernameOfOwnerOfFile "$directory"` #owner  of directory
    local directoryGroup=`f_getGroupnameOfFile "$directory"`       #group  of directory
    
    #Check if the squashfs-directory of the given directory exists, if not create it now
    test    -d "$directoryPD""/squashfs"                        ||  ( 
                                                                        mkdir  $directoryPD"/squashfs"; 
                                                                        chown  $directoryOwner:$directoryGroup $directoryPD"/squashfs";
                                                                        chmod  $directoryRights $directoryPD"/squashfs";
                                                                    )
    rm $directoryPD"/squashfs/"$squashfs_file_name

    #Check if the squashfs of the given directory exists, if not create it now
    test    -f $directoryPD"/squashfs/"$squashfs_file_name      ||  ( 
                                                                        echo " * creating $directoryPD/squashfs/$squashfs_file_name";
                                                                        mksquashfs $directory $directoryPD"/squashfs/"$squashfs_file_name;
                                                                        chown  $directoryOwner:$directoryGroup $directoryPD"/squashfs/"$squashfs_file_name;
                                                                        chmod  $directoryRights $directoryPD"/squashfs/"$squashfs_file_name;
                                                                    )

}

f_HddDirectoryToRamdisk()
{    
    #Funktions parameter
    local directory=$1                                             #directory on HDD which should be loaded into RAM
    local sizeOfRamdisk=$2                                         #maximum size of ramdisk
    local isSquashFS=$3

    #locale variablen
    local hiddenPD="/.physical_disk"
    local hiddenRAM="/.random_access_memory"
    local directoryPD="$hiddenPD""$directory"                      #directory on HDD which is a mountpoint for HDD disk
    local directoryRAM="$hiddenRAM""$directory"                    #directory on HDD which is a mountpoint for RAM disk
    local directoryRights=`f_getOctalFileRights "$directory"`      #rights of directory
    local directoryOwner=`f_getUsernameOfOwnerOfFile "$directory"` #owner  of directory
    local directoryGroup=`f_getGroupnameOfFile "$directory"`       #group  of directory
    local squashfs_file_name="`basename "$directory"".squashfs"`"

    test -d $directoryPD  || (
                                  mkdir -p  $directoryPD;
                                  chmod     $directoryRights $directoryPD;
                                  chown     $directoryOwner:$directoryGroup $directoryPD;
                             )

    test -d $directoryRAM || (
                                  mkdir -p  $directoryRAM; 
                                  chmod     $directoryRights $directoryRAM; 
                                  chown     $directoryOwner:$directoryGroup $directoryRAM;
                             )
     
    echo  "[`date +"%Y-%m-%d %H:%M"`] Synching $directory Ramdisk from HDD" >> /var/log/ramdisk_sync.log
    echo  "Current memory usage is" >> /var/log/ramdisk_sync.log
    free        -t -m >> /var/log/ramdisk_sync.log

    echo  " * synching $directoryPD to ramdisk" #RueckgabeString nach stdout schreiben
    if [ "$isSquashFS" = "true" ];
    then
        #Check if the squashfs-directory of the given directory exists, if not create it now
        test    -d "$directoryPD""/squashfs"                        ||  ( 
                                                                            mkdir  $directoryPD"/squashfs"; 
                                                                            chown  $directoryOwner:$directoryGroup $directoryPD"/squashfs";
                                                                            chmod  $directoryRights $directoryPD"/squashfs";
                                                                        )
        #Check if the squashfs of the given directory exists, if not create it now
        test    -f $directoryPD"/squashfs/"$squashfs_file_name      ||  ( 
                                                                            echo " * creating $directoryPD/squashfs/$squashfs_file_name";
                                                                            mksquashfs $directory $directoryPD"/squashfs/"$squashfs_file_name;
                                                                            chown  $directoryOwner:$directoryGroup $directoryPD"/squashfs/"$squashfs_file_name;
                                                                            chmod  $directoryRights $directoryPD"/squashfs/"$squashfs_file_name;
                                                                        )

        #mount the old directory which is on the physical disk to "$hiddenPD""$directory""/originalfs"
        test    -d "$directoryPD""/originalfs"                      ||  ( 
                                                                            mkdir  $directoryPD"/originalfs";
                                                                            chown  $directoryOwner:$directoryGroup -R $directoryPD"/originalfs";
                                                                            chmod  $directoryRights $directoryPD"/originalfs";
                                                                        )
        mount   --rbind  $directory $directoryPD"/originalfs" -o noatime

        #create the ramdisk file system
        mount   -t tmpfs none $directoryRAM -o size=$sizeOfRamdisk"m"   # m=MB

        #create ramdisk directories
        test    -d "$directoryRAM""/squashfs" || ( 
                                                      mkdir  $directoryRAM"/squashfs"; 
                                                      mkdir  $directoryRAM"/ro"
                                                      mkdir  $directoryRAM"/rw";   
                                                      chown  $directoryOwner:$directoryGroup -R $directoryRAM"/";
                                                      chmod  $directoryRights $directoryRAM
                                                 )
               
        #copy the squashfs file to the ramdisk
        echo   " * synching  $directoryPD/squashfs/$squashfs_file_name to $directoryRAM/squashfs/$squashfs_file_name"
        cp     $directoryPD"/squashfs/"$squashfs_file_name $directoryRAM"/squashfs/"$squashfs_file_name

        #mount $directoryRAM"/squashfs/"$squashfs_file_name into readonly branch
        mount  -t squashfs -o loop,ro,noatime $directoryRAM"/squashfs/"$squashfs_file_name "$directoryRAM""/ro"
        
        #mount to make $directoryRAM"/squashfs/"$squashfs_file_name writeable
        #mount  -t aufs -o noatime,br="$directoryRAM""/aufs/rw":"$directoryRAM""/aufs/ro"=ro aufs  "$directory"
        unionfs -o cow,nonempty "$directoryRAM""/rw"=RW:"$directoryRAM""/ro"=RO "$directory"
    else
        mount  --rbind  $directory $directoryPD
        mount  -t tmpfs none $directoryRAM -o size=$sizeOfRamdisk"m",noatime   # m=MB
        bash -c "
                     #shopt -s dotglob; 
                     #cp -a $directoryPD"/*"  $directoryRAM"/" 1>&2 > /dev/null;
                     #shopt -u dotglob;
                     rsync -av --exclude proc --exclude sys --exclude dev $directoryPD"/*"  $directoryRAM"/" 1>&2 > /dev/null;
                "
        mount  --rbind  $directoryRAM  $directory -o noatime
        umount $directoryRAM
        rm     -r $directoryRAM
    fi

    #echo "directoryRights=$directoryRights"
    #echo "directoryOwner=$directoryOwner"
    #echo "directoryGroup=$directoryGroup"

    chown  $directoryOwner:$directoryGroup $directory
    chmod  $directoryRights                $directory

    #ls -ali $directory"/.."
 
    echo    "Current memory usage is" >> /var/log/ramdisk_sync.log
    free    -t -m >> /var/log/ramdisk_sync.log
    echo     "[`date +"%Y-%m-%d %H:%M"`] $directory Ramdisk Synched from HDD" >> /var/log/ramdisk_sync.log
}

f_RamdiskToHddDirectory()
{
    #Funktions parameter
    local directory=$1                              #directory on RAM which should be synced with HDD
    local isSquashFS=$2
    local isUpdateOriginalFS=$3
     
    #locale variablen
    local hiddenPD="/.physical_disk"
    local hiddenRAM="/.random_access_memory"
    local directoryPD="$hiddenPD""$directory"       #directory on HDD which is a mountpoint for HDD disk
    local directoryRAM="$hiddenRAM""$directory"     #directory on HDD which is a mountpoint for RAM disk

    if [ "$isSquashFS" = "true" ];
    then
        if [ "$isUpdateOriginalFS" = "true" ];
        then
            #synching the original physical disk directory
            local directoryPD=$directoryPD"/originalfs"
            echo " * synching $directoryPD" #RueckgabeString nach stdout schreiben
            rsync -av --delete --exclude proc --exclude sys --exclude dev $directory"/" $directoryPD"/" >> /var/log/ramdisk_sync.log
            echo "[`date +"%Y-%m-%d %H:%M"`] $directory Ramdisk Synched to HD" >> /var/log/ramdisk_sync.log
        fi
        #synching the squashfs file of the original physical disk directory
        echo " * update $directory squashfs?"
        if [ "`f_get_user_answer_yes_no`" = "yes" ];
        then
            f_update_squashfs "$directory"
        fi
        return
    fi
    
    #if [ -n "`mount | grep "$directoryRAM on $directory"`" ];
    if [ -n "`mount | grep "none on $directory"`" ];
    then
        echo " * synching $directoryPD" #RueckgabeString nach stdout schreiben
        rsync -av --delete $directory"/" $directoryPD"/" >> /var/log/ramdisk_sync.log
        echo "[`date +"%Y-%m-%d %H:%M"`] $directory Ramdisk Synched to HD" >> /var/log/ramdisk_sync.log
    else 
        echo "$directory is not a ramdisk"
    fi 
}

f_start()
{
    ####Deleteing old logfile
    rm      /var/log/ramdisk_sync.log.old                           2> /dev/null
    mv      /var/log/ramdisk_sync.log /var/log/ramdisk_sync.log.old 2> /dev/null
    touch   /var/log/ramdisk_sync.log                               2> /dev/null
    
    ####Turning of all Swap-Partitions
    echo " * Checking for swap partitions"
    if [ -n "`cat /proc/swaps  | grep /dev/`" ];
    then
        echo " * Disabling swap partitions: "
        cat /proc/swaps
        swapoff -a
    else 
        echo " * No swap-partition mounted"
    fi 

    echo " * Copying files to Ramdisk"
    
    ####MOVING /bin INTO RAMDISK
    #f_HddDirectoryToRamdisk "/bin" "10" "false"

    ####MOVING /sbin INTO RAMDISK
    #f_HddDirectoryToRamdisk "/sbin" "10" "false"
    
    #####MOVING /etc INTO RAMDISK
    f_HddDirectoryToRamdisk "/etc" "60" "false"
    
    #####MOVING /lib AS SQUASHFS INTO RAMDISK
    f_HddDirectoryToRamdisk "/lib" "100" "true"

    #####MOVING /lib64 AS SQUASHFS INTO RAMDISK
    f_HddDirectoryToRamdisk "/lib64" "30" "true"

    ####MOVING /var INTO RAMDISK
    #f_HddDirectoryToRamdisk "/var" "400" "false"
    #echo " * bindmounting proc mount points"
    #mkdir /var/lib/dhcp/proc
    #mount --bind /proc /var/lib/dhcp/proc
    #mkdir /var/lib/named/proc
    #mount --bind /proc /var/lib/named/proc

    ####MOVING /usr AS SQUASHFS INTO RAMDISK
    f_HddDirectoryToRamdisk "/usr" "400" "true"

    ####MOVING /srv INTO RAMDISK
    f_HddDirectoryToRamdisk "/srv" "100" "false"
    
    ####MOVING /tmp INTO RAMDISK
    f_HddDirectoryToRamdisk "/tmp" "100" "false"
    
    ####MOVING /home INTO RAMDISK
    #f_HddDirectoryToRamdisk "/home/lovgren" "100" "false"
    #chmod 700 /home/lovgren
}

f_sync()
{
    echo " * Synching ramdisk files to harddisk"

    ### First argument is "isSquashFs", second argument is "updateSquashFs"

    ####SYNCHING /bin TO /bin-HDD
    #f_RamdiskToHddDirectory "/bin" "false" "ignored"

    ####SYNCHING /sbin TO /sbin-HDD
    #f_RamdiskToHddDirectory "/sbin" "false" "ignored"

    ####SYNCHING /etc TO /etc-HDD
    f_RamdiskToHddDirectory "/etc" "false" "ignored"

    ####SYNCHING /lib TO /lib-HDD
    f_RamdiskToHddDirectory "/lib" "true" "true"

    ####SYNCHING /lib64 TO /lib-HDD
    f_RamdiskToHddDirectory "/lib64" "true" "true"

    ####SYNCHING /var TO /var-HDD
    #f_RamdiskToHddDirectory "/var" "false" "ignored"

    ####SYNCHING /usr TO /usr-HDD
    f_RamdiskToHddDirectory "/usr" "true" "true"
    
    ####SYNCHING /srv TO /srv-HDD
    f_RamdiskToHddDirectory "/srv" "false" "ignored"
    
    ####SYNCHING /tmp TO /srv-HDD
    f_RamdiskToHddDirectory "/tmp" "false" "ignored"
    
    ####SYNCHING /usr TO /home/trg-HDD
    #f_RamdiskToHddDirectory "/home/lovgren" "false" "ignored"
    
    ####SYNCHING /var TO /var-HDD ein zweites mal um die geaenderte logdatei zu speichern
    #f_RamdiskToHddDirectory "/var" "false" "ignored"
}

f_stop()
{
    echo " * Umounting all squash drives"
    sleep 1
    umount /usr
    sleep 1
    umount /.random_access_memory/usr/ro
    sleep 1
    umount /.random_access_memory/usr
    sleep 1
    umount /.physical_disk/usr/originalfs
    sleep 1
    umount /lib64
    sleep 1
    umount /.random_access_memory/lib64/ro
    sleep 1
    umount /.random_access_memory/lib64
    sleep 1
    umount /.physical_disk/lib64/originalfs
    sleep 1
    umount /lib
    sleep 1
    umount /.random_access_memory/lib/ro
    sleep 1
    umount /.random_access_memory/lib
    sleep 1
    umount /.physical_disk/lib/originalfs
    sleep 1
    umount /srv
    sleep 1
    umount /.physical_disk/srv
    sleep 1
    umount /tmp
    sleep 1
    umount /.physical_disk/tmp
    sleep 1
    umount /etc
    sleep 1
    umount /.physical_disk/etc
    #sleep 1
    #echo " * umounting proc mount points"
    #umount /.physical_disk/var/lock
    #umount /.physical_disk/var/run
    #umount /.physical_disk/var/lib/named/proc
    #umount /.physical_disk/var/lib/dhcp/proc
    #umount /var/lib/named/proc
    #umount /var/lib/dhcp/proc
    #sleep 1
    #umount /var
    #sleep 1
    #umount /.physical_disk/var
}

case "$1" in
  start)
    echo " * Execute ramdisk script?"
    if [ "`f_get_user_answer_yes_no`" = "yes" ];
    then
        echo " * Starting ramdisk script ..."
        f_start
    else 
        echo " * Skipping ramdisk script ..."
    fi
    ;;
  sync)
    f_sync
    ;;
  stop)
    echo " * Execute ramdisk script?"
    if [ "`f_get_user_answer_yes_no`" = "yes" ];
    then
        echo " * Starting ramdisk script ..."
        echo " * Syncing at stop..."
        f_sync
        f_stop
    else 
        echo " * Skipping ramdisk script ..."
    fi
    #echo " * Doing nothing ... All data in /bin /sbin /usr /var /etc /lib /lib32 will not be saved to disk!"
    ;;
  *)
    f_error
    ;;
esac
 
exit 0
