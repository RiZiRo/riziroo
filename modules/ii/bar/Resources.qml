import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

BarWidgetSwitcherArea {
    id: root
    property bool alwaysShowAllResources: false
    property color contentColor: Appearance.colors.colOnSecondaryContainer
    horizontalExtraPadding: 12

    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    rowDefault: Component {
        RowLayout {
            spacing: 0
            Resource {
                iconName: "memory"
                contentColor: root.contentColor
                shown: Config.options.bar.resources.alwaysShowRam
                percentage: ResourceUsage.memoryUsedPercentage
                warningThreshold: Config.options.bar.resources.memoryWarningThreshold
            }
            Resource {
                iconName: "planner_review"
                contentColor: root.contentColor
                shown: Config.options.bar.resources.alwaysShowCpu
                percentage: ResourceUsage.cpuUsage
                Layout.leftMargin: shown ? 6 : 0
                warningThreshold: Config.options.bar.resources.cpuWarningThreshold
            }
            Resource {
                iconName: "thermostat"
                contentColor: root.contentColor
                shown: Config.options.bar.resources.alwaysShowCpuTemp
                percentage: ResourceUsage.cpuTemp / 100
                Layout.leftMargin: shown ? 6 : 0
            }
            Resource {
                iconName: "hard_drive"
                contentColor: root.contentColor
                shown: Config.options.bar.resources.alwaysShowDisk
                percentage: ResourceUsage.diskUsedPercentage
                Layout.leftMargin: shown ? 6 : 0
            }
            Resource {
                iconName: "deployed_code"
                contentColor: root.contentColor
                shown: Config.options.bar.resources.alwaysShowGpu && ResourceUsage.gpuAvailable
                percentage: ResourceUsage.gpuUsage
                Layout.leftMargin: shown ? 6 : 0
                warningThreshold: Config.options.bar.resources.gpuWarningThreshold
            }
        }
    }

    rowMaterial: Component {
        RowLayout {
            spacing: 0
            Resource {
                iconName: "memory"
                contentColor: root.contentColor
                shown: Config.options.bar.resources.alwaysShowRam
                percentage: ResourceUsage.memoryUsedPercentage
                warningThreshold: Config.options.bar.resources.memoryWarningThreshold
            }
            Resource {
                iconName: "planner_review"
                contentColor: root.contentColor
                shown: Config.options.bar.resources.alwaysShowCpu
                percentage: ResourceUsage.cpuUsage
                Layout.leftMargin: shown ? 6 : 0
                warningThreshold: Config.options.bar.resources.cpuWarningThreshold
            }
            Resource {
                iconName: "thermostat"
                contentColor: root.contentColor
                shown: Config.options.bar.resources.alwaysShowCpuTemp
                percentage: ResourceUsage.cpuTemp / 100
                Layout.leftMargin: shown ? 6 : 0
            }
            Resource {
                iconName: "hard_drive"
                contentColor: root.contentColor
                shown: Config.options.bar.resources.alwaysShowDisk
                percentage: ResourceUsage.diskUsedPercentage
                Layout.leftMargin: shown ? 6 : 0
            }
            Resource {
                iconName: "deployed_code"
                contentColor: root.contentColor
                shown: Config.options.bar.resources.alwaysShowGpu && ResourceUsage.gpuAvailable
                percentage: ResourceUsage.gpuUsage
                Layout.leftMargin: shown ? 6 : 0
                warningThreshold: Config.options.bar.resources.gpuWarningThreshold
            }
        }
    }

    colDefault: Component {
        ColumnLayout {
            spacing: 7
            Resource {
                Layout.alignment: Qt.AlignHCenter
                iconName: "memory"
                contentColor: root.contentColor
                vertical: true
                visible: Config.options.bar.resources.alwaysShowRam
                percentage: ResourceUsage.memoryUsedPercentage
                warningThreshold: Config.options.bar.resources.memoryWarningThreshold
            }
            Resource {
                Layout.alignment: Qt.AlignHCenter
                iconName: "planner_review"
                contentColor: root.contentColor
                vertical: true
                visible: Config.options.bar.resources.alwaysShowCpu
                percentage: ResourceUsage.cpuUsage
                warningThreshold: Config.options.bar.resources.cpuWarningThreshold
            }
            Resource {
                Layout.alignment: Qt.AlignHCenter
                iconName: "thermostat"
                contentColor: root.contentColor
                vertical: true
                visible: Config.options.bar.resources.alwaysShowCpuTemp
                percentage: ResourceUsage.cpuTemp / 100
            }
            Resource {
                Layout.alignment: Qt.AlignHCenter
                iconName: "hard_drive"
                contentColor: root.contentColor
                vertical: true
                visible: Config.options.bar.resources.alwaysShowDisk
                percentage: ResourceUsage.diskUsedPercentage
            }
            Resource {
                Layout.alignment: Qt.AlignHCenter
                iconName: "deployed_code"
                contentColor: root.contentColor
                vertical: true
                visible: Config.options.bar.resources.alwaysShowGpu && ResourceUsage.gpuAvailable
                percentage: ResourceUsage.gpuUsage
                warningThreshold: Config.options.bar.resources.gpuWarningThreshold
            }
        }
    }

    colMaterial: Component {
        ColumnLayout {
            spacing: 7
            Resource {
                Layout.alignment: Qt.AlignHCenter
                iconName: "memory"
                contentColor: root.contentColor
                vertical: true
                visible: Config.options.bar.resources.alwaysShowRam
                percentage: ResourceUsage.memoryUsedPercentage
                warningThreshold: Config.options.bar.resources.memoryWarningThreshold
            }
            Resource {
                Layout.alignment: Qt.AlignHCenter
                iconName: "planner_review"
                contentColor: root.contentColor
                vertical: true
                visible: Config.options.bar.resources.alwaysShowCpu
                percentage: ResourceUsage.cpuUsage
                warningThreshold: Config.options.bar.resources.cpuWarningThreshold
            }
            Resource {
                Layout.alignment: Qt.AlignHCenter
                iconName: "thermostat"
                contentColor: root.contentColor
                vertical: true
                visible: Config.options.bar.resources.alwaysShowCpuTemp
                percentage: ResourceUsage.cpuTemp / 100
            }
            Resource {
                Layout.alignment: Qt.AlignHCenter
                iconName: "hard_drive"
                contentColor: root.contentColor
                vertical: true
                visible: Config.options.bar.resources.alwaysShowDisk
                percentage: ResourceUsage.diskUsedPercentage
            }
            Resource {
                Layout.alignment: Qt.AlignHCenter
                iconName: "deployed_code"
                contentColor: root.contentColor
                vertical: true
                visible: Config.options.bar.resources.alwaysShowGpu && ResourceUsage.gpuAvailable
                percentage: ResourceUsage.gpuUsage
                warningThreshold: Config.options.bar.resources.gpuWarningThreshold
            }
        }
    }

    ResourcesPopup {
        hoverTarget: root
    }
}